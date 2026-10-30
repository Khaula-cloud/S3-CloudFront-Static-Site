#!/usr/bin/env bash
# Run from the project root AFTER `terraform apply`:  ./verify.sh
set -e
cd "$(dirname "$0")/terraform"
CF=$(terraform output -raw cloudfront_url)
S3=$(terraform output -raw direct_s3_url_should_fail)
echo "1) Direct S3 access  (expect 403 = bucket is private)"; curl -sI "$S3" | head -n 1
echo "2) CloudFront HTTPS  (expect 200)";                       curl -sI "$CF"  | head -n 1
echo "3) HTTP -> HTTPS     (expect 301/302 redirect)";          curl -sI "${CF/https:/http:}" | head -n 1
echo "4) Cache header      (2nd request should say Hit)";       curl -sI "$CF" >/dev/null; curl -sI "$CF" | grep -i '^x-cache'
echo; echo "Open in browser: $CF"
