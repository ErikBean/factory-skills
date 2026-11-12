// Which stage this synth or deploy is for, and the suffix that keeps its stack
// names apart: dev stacks per branch in the agent account, preview stacks per
// pull request in the preview account, and one prod stack set in production.
// Pass the stage with -c stage=<dev|preview|prod>, plus -c branch=<branch> for
// dev or -c pr=<number> for preview.
import { App } from "aws-cdk-lib";

export type StageName = "dev" | "preview" | "prod";

export interface Stage {
  name: StageName;
  /**
   * Appended to every stack name, such as "-dev-factory-add-login" or
   * "-preview-pr12". Empty for prod, so production stacks keep the names they
   * had before the app had stages.
   */
  suffix: string;
  /**
   * True for dev and preview, whose data is deleted with their stacks. Buckets
   * need it on their own props, since autoDeleteObjects requires a DESTROY
   * removal policy on the bucket itself:
   *   removalPolicy: stage.ephemeral ? RemovalPolicy.DESTROY : RemovalPolicy.RETAIN,
   *   autoDeleteObjects: stage.ephemeral,
   */
  ephemeral: boolean;
  /**
   * For dev, the branch as it appears in stack names. Tag dev stacks with it,
   * as Tags.of(app).add("branch", stage.branch), so the dev cleanup workflow
   * finds them when the branch's pull request closes.
   */
  branch?: string;
}

export function stageFromContext(app: App): Stage {
  const name = app.node.tryGetContext("stage");
  if (name === "prod") return { name, suffix: "", ephemeral: false };
  if (name === "dev") {
    const branch = String(app.node.tryGetContext("branch") ?? "");
    // Stack names allow letters, digits and hyphens, up to 128 characters.
    const slug = branch.replace(/[^A-Za-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60);
    if (!slug) throw new Error("dev needs the branch: -c stage=dev -c branch=<branch>");
    return { name, suffix: `-dev-${slug}`, ephemeral: true, branch: slug };
  }
  if (name === "preview") {
    const pr = String(app.node.tryGetContext("pr") ?? "");
    if (!/^[0-9]+$/.test(pr)) throw new Error("preview needs the pull request number: -c stage=preview -c pr=<number>");
    return { name, suffix: `-preview-pr${pr}`, ephemeral: true };
  }
  throw new Error("Pass the stage: -c stage=dev, preview or prod");
}
