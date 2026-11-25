#!/usr/bin/env bash
# 削除の後に残ったリソースがないことを確かめる。何も出なければ残骸なし。
set -euo pipefail
export AWS_PAGER=""  # aws CLI の出力をページャーで止めない

NAME="${NAME:-tableau-prebuilt}"
REGION="${AWS_REGION:-ap-northeast-1}"
a() { aws --region "$REGION" --output text "$@"; }

echo "== EKS クラスタ ==";      a eks list-clusters --query "clusters[?@=='$NAME']"
echo "== EBS ボリューム ==";    a ec2 describe-volumes --filters "Name=tag:kubernetes.io/cluster/$NAME,Values=owned" --query 'Volumes[].[VolumeId,State]'
                                a ec2 describe-volumes --filters "Name=tag:Project,Values=$NAME" --query 'Volumes[].[VolumeId,State]'
echo "== EFS ==";               a efs describe-file-systems --query "FileSystems[?Name=='${NAME}-bootstrap'].[FileSystemId,LifeCycleState]"
echo "== NAT Gateway ==";       a ec2 describe-nat-gateways --filter "Name=tag:Project,Values=$NAME" "Name=state,Values=pending,available,deleting" --query 'NatGateways[].[NatGatewayId,State]'
echo "== Elastic IP ==";        a ec2 describe-addresses --filters "Name=tag:Project,Values=$NAME" --query 'Addresses[].[AllocationId,PublicIp]'
echo "== VPC ==";               a ec2 describe-vpcs --filters "Name=tag:Project,Values=$NAME" --query 'Vpcs[].VpcId'
echo "== Secrets Manager ==";   a secretsmanager list-secrets --include-planned-deletion --filters "Key=name,Values=$NAME/" --query 'SecretList[].[Name,DeletedDate]'
echo "== KMS キー（PendingDeletion は正常。AWS の仕様で最短 7 日後に消える） =="
for arn in $(a resourcegroupstaggingapi get-resources --resource-type-filters kms:key --tag-filters "Key=Project,Values=$NAME" --query 'ResourceTagMappingList[].ResourceARN'); do
  a kms describe-key --key-id "$arn" --query 'KeyMetadata.[KeyId,KeyState,DeletionDate]'
done
