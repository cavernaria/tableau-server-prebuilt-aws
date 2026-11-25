#!/usr/bin/env bash
# Checks that no resources are left after teardown. No output means nothing is left.
set -euo pipefail
export AWS_PAGER=""  # keep the aws CLI from pausing output in a pager

NAME="${NAME:-tableau-prebuilt}"
REGION="${AWS_REGION:-ap-northeast-1}"
a() { aws --region "$REGION" --output text "$@"; }

echo "== EKS clusters ==";      a eks list-clusters --query "clusters[?@=='$NAME']"
echo "== EBS volumes ==";    a ec2 describe-volumes --filters "Name=tag:kubernetes.io/cluster/$NAME,Values=owned" --query 'Volumes[].[VolumeId,State]'
                                a ec2 describe-volumes --filters "Name=tag:Project,Values=$NAME" --query 'Volumes[].[VolumeId,State]'
echo "== EFS ==";               a efs describe-file-systems --query "FileSystems[?Name=='${NAME}-bootstrap'].[FileSystemId,LifeCycleState]"
echo "== NAT Gateway ==";       a ec2 describe-nat-gateways --filter "Name=tag:Project,Values=$NAME" "Name=state,Values=pending,available,deleting" --query 'NatGateways[].[NatGatewayId,State]'
echo "== Elastic IP ==";        a ec2 describe-addresses --filters "Name=tag:Project,Values=$NAME" --query 'Addresses[].[AllocationId,PublicIp]'
echo "== VPC ==";               a ec2 describe-vpcs --filters "Name=tag:Project,Values=$NAME" --query 'Vpcs[].VpcId'
echo "== Secrets Manager ==";   a secretsmanager list-secrets --include-planned-deletion --filters "Key=name,Values=$NAME/" --query 'SecretList[].[Name,DeletedDate]'
echo "== KMS keys (PendingDeletion is expected; AWS deletes a key after a minimum of 7 days) =="
for arn in $(a resourcegroupstaggingapi get-resources --resource-type-filters kms:key --tag-filters "Key=Project,Values=$NAME" --query 'ResourceTagMappingList[].ResourceARN'); do
  a kms describe-key --key-id "$arn" --query 'KeyMetadata.[KeyId,KeyState,DeletionDate]'
done
