import boto3
import json
import argparse
import logging
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def get_instance_report(region: str, threshold: int):
    try:
        ec2 = boto3.resource('ec2', region_name=region)
        cw = boto3.client('cloudwatch', region_name=region)
        report = []

        instances = ec2.instances.filter(Filters=[{'Name': 'instance-state-name', 'Values': ['running']}])
        
        for inst in instances:
            name = next((t['Value'] for t in inst.tags if t['Key'] == 'Name'), 'Unnamed')
            
            response = cw.get_metric_statistics(
                Namespace='AWS/EC2',
                MetricName='CPUUtilization',
                Dimensions=[{'Name': 'InstanceId', 'Value': inst.id}],
                StartTime=datetime.utcnow() - timedelta(hours=1),
                EndTime=datetime.utcnow(),
                Period=300,
                Statistics=['Average', 'Minimum', 'Maximum']
            )
            
            points = response.get('Datapoints', [])
            if points:
                avg = sum(p['Average'] for p in points) / len(points)
                report.append({
                    "InstanceId": inst.id,
                    "Name": name,
                    "Type": inst.instance_type,
                    "AvgCPU": round(avg, 2),
                    "Alert": avg > threshold
                })
        return report
    except Exception as e:
        logger.error(f"Failed to fetch metrics: {e}")
        return []
