// Smoke-tests a deployed stage: requests every URL the deploy output and
// fails unless each answers with a 2xx or 3xx status. Extend it with checks
// specific to the app. Usage: node scripts/smoke.mjs <outputs.json>
import { stackUrls } from "./stack-urls.mjs";

if (!process.argv[2]) {
  console.error("usage: node scripts/smoke.mjs <outputs.json>");
  process.exit(2);
}

const urls = stackUrls(process.argv[2]);
if (urls.length === 0) {
  console.log("No Url outputs, so there is nothing to smoke-test.");
  process.exit(0);
}

let failed = false;
for (const url of urls) {
  try {
    const response = await fetch(url, { redirect: "manual", signal: AbortSignal.timeout(15000) });
    const ok = response.status >= 200 && response.status < 400;
    console.log(`${ok ? "ok  " : "FAIL"} ${response.status} ${url}`);
    failed ||= !ok;
  } catch (error) {
    console.log(`FAIL ${url}: ${error.message}`);
    failed = true;
  }
}
process.exit(failed ? 1 : 0);
