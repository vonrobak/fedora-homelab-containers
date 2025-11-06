#!/usr/bin/env python3
"""
Alertmanager to Discord Webhook Relay
Transforms Alertmanager webhook payloads to Discord embed format
"""

from flask import Flask, request, jsonify
import requests
import os
import logging
from datetime import datetime

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

DISCORD_WEBHOOK_URL = os.environ.get('DISCORD_WEBHOOK_URL')

def format_discord_embed(alert_data):
    """Convert Alertmanager alert to Discord embed format"""
    embeds = []

    status = alert_data.get('status', 'unknown')

    for alert in alert_data.get('alerts', []):
        labels = alert.get('labels', {})
        annotations = alert.get('annotations', {})

        # Determine color based on status and severity
        if status == 'firing':
            severity = labels.get('severity', 'warning')
            color = 15158332 if severity == 'critical' else 16753920  # Red for critical, orange for warning
            title = f"🚨 {labels.get('alertname', 'Alert')}"
        else:
            color = 3066993  # Green for resolved
            title = f"✅ {labels.get('alertname', 'Alert')} - RESOLVED"

        # Build description
        description = annotations.get('summary', annotations.get('description', 'No description available'))

        # Build fields
        fields = []

        # Add severity
        if 'severity' in labels:
            fields.append({
                'name': 'Severity',
                'value': labels['severity'].upper(),
                'inline': True
            })

        # Add instance
        if 'instance' in labels:
            fields.append({
                'name': 'Instance',
                'value': labels['instance'],
                'inline': True
            })

        # Add service
        if 'service' in labels:
            fields.append({
                'name': 'Service',
                'value': labels['service'],
                'inline': True
            })

        # Add job
        if 'job' in labels:
            fields.append({
                'name': 'Job',
                'value': labels['job'],
                'inline': True
            })

        # Add description if different from summary
        if 'description' in annotations and annotations['description'] != description:
            fields.append({
                'name': 'Details',
                'value': annotations['description'],
                'inline': False
            })

        # Add timestamps
        starts_at = alert.get('startsAt', '')
        if starts_at:
            try:
                dt = datetime.fromisoformat(starts_at.replace('Z', '+00:00'))
                fields.append({
                    'name': 'Started',
                    'value': dt.strftime('%Y-%m-%d %H:%M:%S UTC'),
                    'inline': True
                })
            except:
                pass

        embed = {
            'title': title,
            'description': description,
            'color': color,
            'fields': fields,
            'footer': {
                'text': f"Homelab Monitoring • {alert_data.get('externalURL', 'Alertmanager')}"
            },
            'timestamp': datetime.utcnow().isoformat()
        }

        embeds.append(embed)

    return embeds

@app.route('/webhook', methods=['POST'])
def webhook():
    """Receive Alertmanager webhook and forward to Discord"""
    try:
        alert_data = request.json

        if not alert_data:
            return jsonify({'error': 'No data received'}), 400

        logging.info(f"Received alert: {alert_data.get('status')} - {len(alert_data.get('alerts', []))} alerts")

        # Format for Discord
        embeds = format_discord_embed(alert_data)

        # Send to Discord
        discord_payload = {
            'embeds': embeds
        }

        response = requests.post(
            DISCORD_WEBHOOK_URL,
            json=discord_payload,
            timeout=10
        )

        if response.status_code in [200, 204]:
            logging.info(f"Successfully sent to Discord: {response.status_code}")
            return jsonify({'status': 'success'}), 200
        else:
            logging.error(f"Discord returned {response.status_code}: {response.text}")
            return jsonify({'error': f'Discord returned {response.status_code}'}), 500

    except Exception as e:
        logging.error(f"Error processing webhook: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy'}), 200

if __name__ == '__main__':
    if not DISCORD_WEBHOOK_URL:
        raise ValueError("DISCORD_WEBHOOK_URL environment variable must be set")

    app.run(host='0.0.0.0', port=9095)
