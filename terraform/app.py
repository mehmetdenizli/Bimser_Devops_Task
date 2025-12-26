from flask import Flask, render_template_string
import os

app = Flask(__name__)

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
    <title>Bimser DevOps Task</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f0f2f5; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
        .card { background: white; padding: 40px; border-radius: 15px; box-shadow: 0 10px 25px rgba(0,0,0,0.1); text-align: center; border-top: 8px solid #0056b3; }
        h1 { color: #0056b3; margin-bottom: 10px; }
        p { color: #555; font-size: 18px; }
        .footer { margin-top: 20px; font-size: 12px; color: #888; border-top: 1px solid #eee; padding-top: 15px; }
        .pod-id { font-weight: bold; color: #e67e22; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Merhaba Dünya!</h1>
        <p>Bimser DevOps Task başarıyla çalışıyor.</p>
        <p>Kubernetes Cluster üzerinde Python (Flask) uygulaması yayında.</p>
        <div class="footer">
            Yanıt Veren Pod: <span class="pod-id">{{ pod_name }}</span>
        </div>
    </div>
</body>
</html>
"""

@app.route('/')
def hello():
    pod_name = os.getenv('HOSTNAME', 'Local Bilgisayar')
    return render_template_string(HTML_TEMPLATE, pod_name=pod_name)

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=5000)