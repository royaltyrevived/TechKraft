import boto3, json, argparse, logging
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def load_config(path='config.json'):
    try:
        with open(path, 'r') as f:
            return json.load(f) [cite: 155]
    except FileNotFoundError:
        logger.error("config.json not found")
        return {"alert_threshold": 80, "regions": ["us-east-1"]}

def monitor_region(region, threshold):
    ec2 = boto3.resource('ec2', region_name=region)
    cw = boto3.client('cloudwatch', region_name=region)
    report = []
    
    try:
        instances = ec2.instances.filter(Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]) [cite: 149]
        for inst in instances:
            name = next((t['Value'] for t in inst.tags if t['Key'] == 'Name'), 'N/A') [cite: 152]
            res = cw.get_metric_statistics(
                Namespace='AWS/EC2', MetricName='CPUUtilization',
                Dimensions=[{'Name': 'InstanceId', 'Value': inst.id}],
                StartTime=datetime.utcnow()-timedelta(hours=1), EndTime=datetime.utcnow(),
                Period=300, Statistics=['Average', 'Minimum', 'Maximum'] [cite: 150, 153]
            )
            pts = res.get('Datapoints', [])
            if pts:
                avg = sum(p['Average'] for p in pts) / len(pts)
                report.append({
                    "InstanceId": inst.id, "Name": name, "Type": inst.instance_type,
                    "AvgCPU": round(avg, 2), "Alert": avg > threshold [cite: 154]
                })
        return report
    except Exception as e:
        logger.error(f"AWS API Error in {region}: {e}") [cite: 156]
        return []

if __name__ == "__main__":
    conf = load_config()
    parser = argparse.ArgumentParser() [cite: 158]
    parser.add_argument("--region", default=conf['regions'][0])
    parser.add_argument("--threshold", type=int, default=conf['alert_threshold'])
    parser.add_argument("--output", default="report.json")
    args = parser.parse_args()
    
    final_report = monitor_region(args.region, args.threshold)
    with open(args.output, 'w') as f:
        json.dump(final_report, f, indent=4)
    logger.info(f"Report exported to {args.output}")
