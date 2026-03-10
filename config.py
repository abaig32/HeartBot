import os 
from dotenv import load_dotenv

load_dotenv()

API_URL = os.getenv("API_URL")
APP_TITLE = "HeartBot"
APP_DESCRIPTION = "Ask me about heart health and symptoms!"
MAX_RETRIES = 3
REQUEST_TIMEOUT = 30

