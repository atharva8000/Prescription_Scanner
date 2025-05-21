from flask import Flask, request, jsonify
import cv2
import numpy as np
import os
import re
from werkzeug.utils import secure_filename
import requests
import json
from datetime import datetime
from pymongo import MongoClient
from pymongo import MongoClient
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# Configuration
UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg'}
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB max

# Updated Azure OCR configuration
AZURE_OCR_ENDPOINT = "https://prescscan.cognitiveservices.azure.com/vision/v3.2/read/analyze"
AZURE_OCR_KEY = "5jWqIRNYkD9s2VuRJ0BM366IUd8VebBWUBgRA4RSNXiy6zmtHP4QJQQJ99BEACYeBjFXJ3w3AAAFACOGedSd"

os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# MongoDB Connection
client = MongoClient('mongodb://localhost:27017/')
db = client['med_scanner_app']
prescriptions_collection = db['prescriptions']
users_collection = db['users']

# =================== Helper Functions ===================

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def preprocess_image(image_bytes):
    """Improve image quality before OCR"""
    nparr = np.frombuffer(image_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    
    # Convert to grayscale
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    
    # Apply adaptive thresholding
    processed = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
                                    cv2.THRESH_BINARY, 11, 2)
    
    # Denoising
    processed = cv2.fastNlMeansDenoising(processed, None, 10, 7, 21)
    
    _, img_bytes = cv2.imencode('.jpg', processed)
    return img_bytes.tobytes()

def extract_text_azure(image_bytes):
    """Improved Azure OCR text extraction"""
    headers_azure = {
        'Ocp-Apim-Subscription-Key': AZURE_OCR_KEY,
        'Content-Type': 'application/octet-stream'
    }

    try:
        # Preprocess the image before sending to OCR
        processed_image = preprocess_image(image_bytes)
        
        response = requests.post(AZURE_OCR_ENDPOINT, headers=headers_azure, data=processed_image)
        if response.status_code != 202:
            print("Azure OCR Error:", response.text)
            return ""

        operation_url = response.headers["Operation-Location"]

        import time
        max_attempts = 10
        for _ in range(max_attempts):
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
    except Exception as e:
        print(f"Error in Azure OCR: {str(e)}")
        return ""

def extract_medicines(text):
    """Improved medicine name extraction using regex patterns"""
    # Common patterns in prescriptions
    patterns = [
        r'\b([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\b',  # Capitalized words
        r'\b\d+\s*(mg|g|ml|tablet|tab|cap|capsule)\b',  # Dosage info
        r'\b[A-Z]{2,}\b',  # All caps words (often medicine names)
        r'\b[a-z]+\s*\d+[a-z]*\b',  # Alphanumeric combinations
    ]
    
    medicines = set()
    
    # First extract using patterns
    for pattern in patterns:
        matches = re.findall(pattern, text)
        for match in matches:
            if isinstance(match, tuple):
                match = match[0]  # Get the first group if it's a tuple
            if len(match) > 3:  # Ignore very short matches
                medicines.add(match.strip())
    
    # Then look for lines that might contain medicine names
    for line in text.split('\n'):
        line = line.strip()
        if not line:
            continue
            
        # Common prescription indicators
        if any(keyword in line.lower() for keyword in ['tab', 'cap', 'mg', 'ml', 'inj', 'ointment']):
            # Clean the line
            cleaned = re.sub(r'[^\w\s-]', '', line)  # Remove special chars except space and hyphen
            medicines.add(cleaned.strip())
    
    return sorted(medicines, key=lambda x: -len(x))  # Sort by length descending

def format_extracted_text(text):
    """Format the extracted text for better readability"""
    # Split into lines and clean each line
    lines = [line.strip() for line in text.split('\n') if line.strip()]
    
    # Group related lines (like medicine name with dosage)
    formatted_lines = []
    i = 0
    while i < len(lines):
        current_line = lines[i]
        
        # Check if next line might be continuation (no capital letter at start)
        if i + 1 < len(lines) and not lines[i+1][0].isupper():
            current_line += " " + lines[i+1]
            i += 1
            
        formatted_lines.append(current_line)
        i += 1
    
    return "\n".join(formatted_lines)

# =================== API Routes ===================

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
        try:
            image_bytes = file.read()

            # Extract text
            text = extract_text_azure(image_bytes)
            if not text:
                return jsonify({'error': 'Text extraction failed'}), 400

            # Extract medicines
            medicines = extract_medicines(text)
            
            # Format the extracted text
            formatted_text = format_extracted_text(text)

            # Save to MongoDB
            timestamp = datetime.now()
            prescription_document = {
                "user_id": user_id,
                "extracted_text": formatted_text,
                "medicines": list(medicines),
                "created_at": timestamp
            }
            
            result = prescriptions_collection.insert_one(prescription_document)
            prescription_id = str(result.inserted_id)

            # Save the file
            filename = secure_filename(f"{prescription_id}_{file.filename}")
            file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            with open(file_path, 'wb') as f:
                f.write(image_bytes)
                
            # Update the document with the file path
            prescriptions_collection.update_one(
                {"_id": result.inserted_id},
                {"$set": {"image_path": file_path}}
            )

            return jsonify({
                'text_extracted': formatted_text,
                'medicines_found': list(medicines),
                'user_id': user_id,
                'prescription_id': prescription_id,
                'timestamp': timestamp.strftime('%Y-%m-%d %H:%M:%S')
            }), 200

        except Exception as e:
            return jsonify({'error': str(e)}), 500

    return jsonify({'error': 'File type not allowed'}), 400

# Additional API routes for user management

@app.route('/register_user', methods=['POST'])
def register_user():
    data = request.json
    if not data or not all(k in data for k in ['username', 'email', 'password']):
        return jsonify({'error': 'Missing required fields'}), 400
    
    # Check if user already exists
    existing_user = users_collection.find_one({'email': data['email']})
    if existing_user:
        return jsonify({'error': 'User already exists'}), 409
    
    # Hash password
    hashed_password = bcrypt.hashpw(data['password'].encode('utf-8'), bcrypt.gensalt())
    
    # Create user document
    user_document = {
        'username': data['username'],
        'email': data['email'],
        'password': hashed_password,
        'created_at': datetime.now()
    }
    
    result = users_collection.insert_one(user_document)
    
    return jsonify({
        'success': True,
        'user_id': str(result.inserted_id)
    }), 201

@app.route('/user_prescriptions/<user_id>', methods=['GET'])
def get_user_prescriptions(user_id):
    prescriptions = prescriptions_collection.find({'user_id': user_id})
    result = []
    
    for prescription in prescriptions:
        prescription['_id'] = str(prescription['_id'])  # Convert ObjectId to string
        if 'created_at' in prescription:
            prescription['created_at'] = prescription['created_at'].strftime('%Y-%m-%d %H:%M:%S')
        result.append(prescription)
    
    return jsonify(result), 200

@app.route('/')
def test_page():
    return '''
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Prescription Scanner Tester</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                max-width: 800px;
                margin: 0 auto;
                padding: 20px;
                line-height: 1.6;
            }
            .container {
                background-color: #f9f9f9;
                border-radius: 8px;
                padding: 20px;
                margin-top: 20px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            input, button {
                padding: 10px;
                margin: 10px 0;
            }
            button {
                background-color: #4CAF50;
                color: white;
                border: none;
                border-radius: 4px;
                cursor: pointer;
            }
            button:hover {
                background-color: #45a049;
            }
            pre {
                background-color: #f0f0f0;
                padding: 15px;
                border-radius: 4px;
                overflow-x: auto;
            }
            .response {
                margin-top: 20px;
            }
            #loader {
                display: none;
                border: 5px solid #f3f3f3;
                border-top: 5px solid #3498db;
                border-radius: 50%;
                width: 30px;
                height: 30px;
                animation: spin 2s linear infinite;
                margin: 20px auto;
            }
            @keyframes spin {
                0% { transform: rotate(0deg); }
                100% { transform: rotate(360deg); }
            }
        </style>
    </head>
    <body>
        <h1>Prescription Scanner API Tester</h1>
        <div class="container">
            <h2>Upload Prescription</h2>
            <form id="prescriptionForm">
                <div>
                    <label for="user_id">User ID:</label>
                    <input type="text" id="user_id" name="user_id" value="1" required>
                </div>
                <div>
                    <label for="image">Prescription Image:</label>
                    <input type="file" id="image" name="image" accept="image/png, image/jpeg" required>
                </div>
                <button type="submit">Upload and Process</button>
            </form>
            <div id="loader"></div>
            <div class="response">
                <h3>API Response:</h3>
                <pre id="response">No response yet</pre>
            </div>
        </div>

        <script>
            document.getElementById('prescriptionForm').addEventListener('submit', async function(e) {
                e.preventDefault();
                
                const loader = document.getElementById('loader');
                const responseElement = document.getElementById('response');
                
                loader.style.display = 'block';
                responseElement.textContent = 'Processing...';
                
                const formData = new FormData();
                formData.append('user_id', document.getElementById('user_id').value);
                formData.append('image', document.getElementById('image').files[0]);
                
                try {
                    const response = await fetch('/process_prescription', {
                        method: 'POST',
                        body: formData
                    });
                    
                    const data = await response.json();
                    responseElement.textContent = JSON.stringify(data, null, 2);
                    
                } catch (error) {
                    responseElement.textContent = `Error: ${error.message}`;
                    console.error('Fetch error:', error);
                } finally {
                    loader.style.display = 'none';
                }
            });
        </script>
    </body>
    </html>
    '''

# Add a route to access uploaded images
@app.route('/uploads/<filename>')
def uploaded_file(filename):
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)

if __name__ == '__main__':
    app.run(debug=True)