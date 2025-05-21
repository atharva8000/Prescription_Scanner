from flask import Flask, request, jsonify
import cv2
import numpy as np
import os
import re
from werkzeug.utils import secure_filename
import requests
import json
import pymysql
import bcrypt

app = Flask(__name__)

# Configuration
UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg'}
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB max

HF_API_URL = "https://api-inference.huggingface.co/models/dslim/bert-base-NER"
HF_API_TOKEN = "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"
headers = {
    "Authorization": f"Bearer {HF_API_TOKEN}",
    "Content-Type": "application/json"
}

AZURE_OCR_ENDPOINT = "https://prescscan.cognitiveservices.azure.com/"
AZURE_OCR_KEY = "5jWqIRNYkD9s2VuRJ0BM366IUd8VebBWUBgRA4RSNXiy6zmtHP4QJQQJ99BEACYeBjFXJ3w3AAAFACOGedSd"

os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# MySQL Connection
db = pymysql.connect(
    host="localhost",
    user="root",
    password="atharva",
    database="med_scanner_app"
)
cursor = db.cursor()

# =================== Auth Routes ===================

@app.route('/signup', methods=['POST'])
def signup():
    data = request.get_json()
    email = data.get('email')
    password = data.get('password')

    if not email or not password:
        return jsonify({'error': 'Email and password required'}), 400

    hashed_pw = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt())

    try:
        cursor.execute("INSERT INTO users (email, password) VALUES (%s, %s)", (email, hashed_pw))
        db.commit()
        return jsonify({'message': 'User registered successfully'}), 201
    except pymysql.err.IntegrityError:
        return jsonify({'error': 'User already exists'}), 409

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    email = data.get('email')
    password = data.get('password')

    cursor.execute("SELECT id, password FROM users WHERE email=%s", (email,))
    result = cursor.fetchone()

    if result and bcrypt.checkpw(password.encode('utf-8'), result[1].encode('utf-8')):
        return jsonify({'message': 'Login successful', 'user_id': result[0]}), 200
    else:
        return jsonify({'error': 'Invalid credentials'}), 401

# =================== Medicine Processing ===================

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def extract_text_azure(image_bytes):
    url = AZURE_OCR_ENDPOINT + "vision/v3.2/read/analyze"
    headers_azure = {
        'Ocp-Apim-Subscription-Key': AZURE_OCR_KEY,
        'Content-Type': 'application/octet-stream'
    }

    response = requests.post(url, headers=headers_azure, data=image_bytes)
    if response.status_code != 202:
        print("Azure OCR Error:", response.text)
        return ""

    operation_url = response.headers["Operation-Location"]

    import time
    for _ in range(10):
        time.sleep(1)
        result = requests.get(operation_url, headers={'Ocp-Apim-Subscription-Key': AZURE_OCR_KEY})
        result_json = result.json()

        if result_json['status'] == 'succeeded':
            lines = []
            for read_result in result_json['analyzeResult']['readResults']:
                for line in read_result['lines']:
                    lines.append(line['text'])
            return "\n".join(lines)
        elif result_json['status'] == 'failed':
            return ""

    return ""

def extract_medicines_via_ner(text):
    response = requests.post(HF_API_URL, headers=headers, data=json.dumps({"inputs": text}))
    if response.status_code != 200:
        print("Hugging Face API Error:", response.text)
        return []

    predictions = response.json()
    medicine_entities = []

    for ent in predictions:
        if ent['entity_group'] in ['ORG', 'MISC', 'PER']:
            word = ent['word'].replace('##', '')
            if word not in medicine_entities:
                medicine_entities.append(word)

    return medicine_entities

@app.route('/process_prescription', methods=['POST'])
def process_prescription():
    if 'user_id' not in request.form:
        return jsonify({'error': 'user_id required'}), 400
    user_id = request.form['user_id']

    if 'image' not in request.files:
        return jsonify({'error': 'No image provided'}), 400

    file = request.files['image']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400

    if file and allowed_file(file.filename):
        image_bytes = file.read()

        text = extract_text_azure(image_bytes)
        medicines = extract_medicines_via_ner(text)

        filename = secure_filename(file.filename)
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        with open(file_path, 'wb') as f:
            f.write(image_bytes)

        cursor.execute("INSERT INTO prescriptions (user_id, extracted_text) VALUES (%s, %s)", (user_id, text))
        db.commit()

        return jsonify({
            'text_extracted': text,
            'medicines_found': medicines,
            'user_id': user_id
        }), 200

    return jsonify({'error': 'File type not allowed'}), 400

if __name__ == '__main__':
    app.run(debug=True)