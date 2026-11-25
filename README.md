# tableau-server-prebuilt-aws

Tableau Server のプレビルトイメージを、公式 Helm チャートで EKS に立てる検証。イメージはビルドせず、Docker Hub のプレビルトイメージをそのまま使う。

- 単一ノード構成: ノード 1 つ（既定）
- マルチノード構成: 初期ノード 1 つとワーカー 2 つ

構成は `TOPOLOGY` で切り替える。`terraform/` と `scripts/` は両方の構成で共通で、マルチノード構成のときだけ EFS とワーカー用のノードグループを作る。

## 前提

- `terraform`、`aws`、`kubectl`、`helm`、`jq` が入っている
- AWS の認証が通っている（例: `export AWS_PROFILE=<プロファイル名>` のあと `aws sso login`）
- `terraform/terraform.tfvars` に `api_allowed_cidrs` がある。値は `checkip` ではなく、CloudTrail の `sourceIPAddress` で確かめた送信元にする
- `k8s/reg-info.local.json` がある（`k8s/reg-info.example.json` を写して埋める）
- Secrets Manager の `tableau-prebuilt/license-key` と `tableau-prebuilt/admin-password` に値が入っている。初回は `terraform apply` のあとに入れる

## 使い方

| やること | コマンド |
|---|---|
| 立ち上げ（plan の確認 → 作成 → Tableau Server の起動）。単一ノード構成 | `./scripts/up.sh` |
| 同上。マルチノード構成 | `TOPOLOGY=multi ./scripts/up.sh` |
| クラスタの状態（Pod、Tableau のノード、プロセス）の表示 | `./scripts/status.sh` |
| 接続（実行中だけ `http://localhost:8080` で使える） | `./scripts/connect.sh` |
| 削除（認証解除 → Tableau Server の削除 → AWS のリソースの削除） | `./scripts/down.sh` |
| 削除の後の残骸の確認 | `./scripts/check-leftovers.sh` |
| Tableau Server だけ入れ直す | `./scripts/deploy.sh` |

`TOPOLOGY` を付けずに実行すると、どのスクリプトも、いま立っている環境の構成に合わせる。何も立っていなければ単一ノード構成になる。

ログインのユーザー名は `admin`。パスワードは次で取り出す。

```
aws secretsmanager get-secret-value --region ap-northeast-1 \
  --secret-id tableau-prebuilt/admin-password --query SecretString --output text | pbcopy
```

`up.sh`、`down.sh`、`deploy.sh` の出力は `.cache/<名前>.log` にも残る（ライセンスキーの形の文字列は伏せ字）。

どのスクリプトも、途中で失敗したらもう一度実行すれば続きから進む。稼働中はインスタンス、NAT Gateway、EKS の課金が続くので、検証が終わったら削除する。
