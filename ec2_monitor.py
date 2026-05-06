import boto3, json, argparse, logging
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def monitor(region, threshold, output):
    ec2 = boto3.resource('ec2', region_name=region)
    cw = boto3.client('cloudwatch', region_name=region)
    report = []
    
    try:
        instances = ec2.instances.filter(Filters=[{'Name': 'instance-state-name', 'Values': ['running']}])
        for inst in instances:
            res = cw.get_metric_statistics(
                Namespace='AWS/EC2', MetricName='CPUUtilization',
                Dimensions=[{'Name': 'InstanceId', 'Value': inst.id}],
                StartTime=datetime.utcnow()-timedelta(hours=1), EndTime=datetime.utcnow(),
                Period=300, Statistics=['Average', 'Minimum', 'Maximum']
            )
            pts = res.get('Datapoints', [])
            avg = sum(p['Average'] for p in pts) / len(pts) if pts else 0
            report.append({
                "InstanceId": inst.id, 
                "AvgCPU": round(avg, 2), 
                "Alert": avg > threshold
            })
        
        with open(output, 'w') as f:
            json.dump(report, f, indent=4)
        logger.info(f"Report exported to {output}")
    except Exception as e:
        logger.error(f"AWS API Error: {e}")

if __name__ == "__main__":
    with open('config.json', 'r') as f:
        conf = json.load(f)
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", default=conf['regions'][0])
    parser.add_argument("--threshold", type=int, default=conf['alert_threshold'])
    parser.add_argument("--output", default="report.json")
    args = parser.parse_args()
    monitor(args.region, args.threshold, args.output)
