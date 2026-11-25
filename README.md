# tableau-server-prebuilt-aws

Code for trying out the Tableau Server prebuilt container image on Amazon EKS with the official Helm chart. Nothing is built locally: the prebuilt image is pulled from Docker Hub as is.

- Single-node topology: one node (default)
- Multi-node topology: one initial node and two workers

Switch between them with `TOPOLOGY`. `terraform/` and `scripts/` are shared by both topologies. The EFS file system and the instances for the workers are created only for the multi-node topology.

## Prerequisites

- `terraform`, `aws`, `kubectl`, `helm`, `jq`, `curl`, `tar`, and `shasum` are installed
- You are authenticated to AWS (for example, `export AWS_PROFILE=<profile name>` followed by `aws sso login`)
- `terraform/terraform.tfvars` sets `api_allowed_cidrs`. Use the source address you confirmed in CloudTrail (`sourceIPAddress`), not the one reported by `checkip`
- `k8s/reg-info.local.json` exists (copy `k8s/reg-info.example.json` and fill it in)
- The Secrets Manager secrets `tableau-prebuilt/license-key` and `tableau-prebuilt/admin-password` hold values (see [First run](#first-run))

## First run

Terraform creates the two secrets empty, so their values never reach the Terraform state. On the first run, `./scripts/up.sh` creates the AWS resources and then stops with a message that the secrets have no value. Set both values, then run `./scripts/up.sh` again. It continues from the installation of Tableau Server.

Read each value from the terminal and pass it on stdin, so that it does not end up in your shell history or in a command argument:

```
read -rs VALUE
printf '%s' "$VALUE" | aws secretsmanager put-secret-value --region ap-northeast-1 \
  --secret-id tableau-prebuilt/license-key --secret-string file:///dev/stdin >/dev/null
unset VALUE
```

Do the same for `tableau-prebuilt/admin-password`.

If your account stops instances on a schedule and needs a tag to opt out, pass it in `terraform/terraform.tfvars`, for example `extra_node_tags = { "<tag key>" = "<tag value>" }`. A stopped instance is replaced, which restarts Tableau Server.

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

Without `TOPOLOGY`, `up.sh` and `deploy.sh` follow the topology of the environment that is currently up. If nothing is up, they use the single-node topology. The other scripts work with either topology and do not read `TOPOLOGY`.

The login user name is `admin`. Copy the password to the clipboard with (`pbcopy` is macOS only):

```
aws secretsmanager get-secret-value --region ap-northeast-1 \
  --secret-id tableau-prebuilt/admin-password --query SecretString --output text | pbcopy
```

The output of `up.sh`, `down.sh`, and `deploy.sh` is also saved to `.cache/<name>.log` (strings shaped like a license key are redacted).

If a script fails partway, run it again and it continues from where it stopped. `down.sh` stops if it cannot reach the cluster, because it could not deactivate the license; `FORCE=1 ./scripts/down.sh` continues anyway. The instances, the NAT Gateway, and EKS are billed while the environment is up, so tear it down when you are done.
