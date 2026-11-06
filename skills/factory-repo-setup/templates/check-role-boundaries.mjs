// Fails if any IAM role or user in the synthesized CDK templates has no
// permissions boundary. Run after `cdk synth`. It catches roles the
// @aws-cdk/core:permissionsBoundary context key misses, such as the one behind
// AwsCustomResource (aws/aws-cdk#30179), before a deploy fails on them.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

function templates(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return templates(path);
    return name.endsWith(".template.json") ? [path] : [];
  });
}

const missing = [];
for (const file of templates("cdk.out")) {
  const { Resources = {} } = JSON.parse(readFileSync(file, "utf8"));
  for (const [id, resource] of Object.entries(Resources)) {
    const bounded = ["AWS::IAM::Role", "AWS::IAM::User"].includes(resource.Type);
    if (bounded && !resource.Properties?.PermissionsBoundary) missing.push(`${file}: ${id}`);
  }
}

if (missing.length > 0) {
  console.error(`IAM roles or users without a permissions boundary:\n${missing.join("\n")}`);
  process.exit(1);
}
console.log("Every IAM role and user has a permissions boundary.");
