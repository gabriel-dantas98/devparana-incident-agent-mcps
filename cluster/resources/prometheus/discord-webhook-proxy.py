#!/usr/bin/env python3
import json
import requests
from flask import Flask, request, jsonify
import logging
from datetime import datetime

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# Discord webhook URL
DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/1414837697507233932/bgl6XO7pPiBmmWaxKKiPk8-nQe4op7vgxHeMTFFN-AJXwcg4vzd95KadwnqJPmkwY8Kn"

def format_alert_message(alert_data):
    """Transform Alertmanager payload to Discord message"""
    status = alert_data.get('status', 'unknown')
    alerts = alert_data.get('alerts', [])
    
    if not alerts:
        return "⚠️ Alerta sem detalhes"
    
    messages = []
    
    for alert in alerts:
        alert_status = alert.get('status', status)
        labels = alert.get('labels', {})
        annotations = alert.get('annotations', {})
        
        # Get alert details
        alertname = labels.get('alertname', 'Unknown Alert')
        instance = labels.get('instance', 'Unknown Instance')
        severity = labels.get('severity', 'unknown')
        summary = annotations.get('summary', 'No summary available')
        description = annotations.get('description', 'No description available')
        
        # Status emoji
        if alert_status == 'firing':
            if severity == 'critical':
                emoji = '🚨'
            elif severity == 'warning':
                emoji = '⚠️'
            else:
                emoji = '🔴'
        else:
            emoji = '✅'
        
        # Format message
        message = f"{emoji} **{alertname}** ({alert_status.upper()})\n"
        message += f"**Resumo:** {summary}\n"
        message += f"**Descrição:** {description}\n"
        message += f"**Instance:** {instance}\n"
        message += f"**Severidade:** {severity}\n"
        
        # Add timestamp if available
        if 'startsAt' in alert:
            try:
                start_time = alert['startsAt']
                message += f"**Início:** {start_time}\n"
            except:
                pass
                
        messages.append(message)
    
    return "\n---\n".join(messages)

@app.route('/webhook', methods=['POST'])
def webhook():
    try:
        # Get Alertmanager payload
        alert_data = request.get_json()
        app.logger.info(f"Received payload: {json.dumps(alert_data, indent=2)}")
        
        # Transform to Discord format
        discord_message = format_alert_message(alert_data)
        
        # Send to Discord
        discord_payload = {
            "content": discord_message
        }
        
        app.logger.info(f"Sending to Discord: {discord_message[:100]}...")
        
        response = requests.post(DISCORD_WEBHOOK_URL, json=discord_payload)
        
        if response.status_code == 204:
            app.logger.info("Successfully sent to Discord")
            return jsonify({"status": "success"}), 200
        else:
            app.logger.error(f"Discord API error: {response.status_code} - {response.text}")
            return jsonify({"status": "error", "message": response.text}), 500
            
    except Exception as e:
        app.logger.error(f"Error processing webhook: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
