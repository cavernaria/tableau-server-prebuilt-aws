# tableau-server-prebuilt-aws

Code for trying out the Tableau Server prebuilt container image on Amazon EKS with the official Helm chart. Nothing is built locally: the prebuilt image is pulled from Docker Hub as is.

- Single-node topology: one node (default)
- Multi-node topology: one initial node and two workers

Switch between them with `TOPOLOGY`. `terraform/` and `scripts/` are shared by both topologies. The EFS file system and the worker node group are created only for the multi-node topology.

## Prerequisites

- `terraform`, `aws`, `kubectl`, `helm`, and `jq` are installed
- You are authenticated to AWS (for example, `export AWS_PROFILE=<profile name>` followed by `aws sso login`)
- `terraform/terraform.tfvars` sets `api_allowed_cidrs`. Use the source address you confirmed in CloudTrail (`sourceIPAddress`), not the one reported by `checkip`
- `k8s/reg-info.local.json` exists (copy `k8s/reg-info.example.json` and fill it in)
- The Secrets Manager secrets `tableau-prebuilt/license-key` and `tableau-prebuilt/admin-password` hold values. On the first run, set them after `terraform apply`

## Usage

| Task | Command |
|---|---|
| Bring up (review the plan → create → start Tableau Server), single-node topology | `./scripts/up.sh` |
| Same, multi-node topology | `TOPOLOGY=multi ./scripts/up.sh` |
| Show the cluster status (Pods, Tableau nodes, processes) | `./scripts/status.sh` |
| Connect (`http://localhost:8080` works only while this is running) | `./scripts/connect.sh` |
| Tear down (deactivate the license → remove Tableau Server → delete the AWS resources) | `./scripts/down.sh` |
| Check for leftovers after teardown | `./scripts/check-leftovers.sh` |
| Reinstall Tableau Server only | `./scripts/deploy.sh` |

Without `TOPOLOGY`, every script follows the topology of the environment that is currently up. If nothing is up, it uses the single-node topology.

The login user name is `admin`. Retrieve the password with:

```
aws secretsmanager get-secret-value --region ap-northeast-1 \
  --secret-id tableau-prebuilt/admin-password --query SecretString --output text | pbcopy
```

The output of `up.sh`, `down.sh`, and `deploy.sh` is also saved to `.cache/<name>.log` (strings shaped like a license key are redacted).

If a script fails partway, run it again and it continues from where it stopped. The instances, the NAT Gateway, and EKS are billed while the environment is up, so tear it down when you are done.
