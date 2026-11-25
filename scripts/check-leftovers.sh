#!/usr/bin/env bash
# Checks that no resources are left after teardown. Nothing listed under a heading means nothing is left.
set -euo pipefail
export AWS_PAGER=""  # keep the aws CLI from pausing output in a pager

NAME="${NAME:-tableau-prebuilt}"
REGION="${AWS_REGION:-ap-northeast-1}"
aws_text() { aws --region "$REGION" --output text "$@"; }

echo "== EKS clusters ==";      aws_text eks list-clusters --query "clusters[?@=='$NAME']"
echo "== EBS volumes ==";    aws_text ec2 describe-volumes --filters "Name=tag:kubernetes.io/cluster/$NAME,Values=owned" --query 'Volumes[].[VolumeId,State]'
                                aws_text ec2 describe-volumes --filters "Name=tag:Project,Values=$NAME" --query 'Volumes[].[VolumeId,State]'
echo "== EFS ==";               aws_text efs describe-file-systems --query "FileSystems[?Name=='${NAME}-bootstrap'].[FileSystemId,LifeCycleState]"
echo "== EFS mount targets =="
for fs in $(aws_text efs describe-file-systems --query "FileSystems[?Name=='${NAME}-bootstrap'].FileSystemId"); do
  aws_text efs describe-mount-targets --file-system-id "$fs" --query 'MountTargets[].[MountTargetId,LifeCycleState]'
done
echo "== Security groups ==";   aws_text ec2 describe-security-groups --filters "Name=tag:Project,Values=$NAME" --query 'SecurityGroups[].[GroupId,GroupName]'
echo "== NAT Gateway ==";       aws_text ec2 describe-nat-gateways --filter "Name=tag:Project,Values=$NAME" "Name=state,Values=pending,available,deleting" --query 'NatGateways[].[NatGatewayId,State]'
echo "== Elastic IP ==";        aws_text ec2 describe-addresses --filters "Name=tag:Project,Values=$NAME" --query 'Addresses[].[AllocationId,PublicIp]'
echo "== VPC ==";               aws_text ec2 describe-vpcs --filters "Name=tag:Project,Values=$NAME" --query 'Vpcs[].VpcId'
echo "== Secrets Manager ==";   aws_text secretsmanager list-secrets --include-planned-deletion --filters "Key=name,Values=$NAME/" --query 'SecretList[].[Name,DeletedDate]'
echo "== KMS keys (PendingDeletion is expected; AWS deletes a key after a minimum of 7 days) =="
for arn in $(aws_text resourcegroupstaggingapi get-resources --resource-type-filters kms:key --tag-filters "Key=Project,Values=$NAME" --query 'ResourceTagMappingList[].ResourceARN'); do
  aws_text kms describe-key --key-id "$arn" --query 'KeyMetadata.[KeyId,KeyState,DeletionDate]'
done
