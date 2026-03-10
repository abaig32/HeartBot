import requests
from config import API_URL, MAX_RETRIES, REQUEST_TIMEOUT

def query_heartbot(user_input: str) -> dict:
    payload = {"query": user_input}

    for attempt in range(MAX_RETRIES):
        try:
            response = requests.post(
                API_URL,
                json=payload,
                timeout=REQUEST_TIMEOUT
            )
            response.raise_for_status()
            return response.json()
        
        except requests.exceptions.Timeout:
            if attempt == MAX_RETRIES - 1:
                return {"error": "Request times out. Please try again."}
        
        except requests.exceptions.ConnectionError:
            if attempt == MAX_RETRIES - 1:
                return {"error": "Could not connect to the server. Check your connection"}
        
        except requests.exceptions.HTTPError as e:
            return {"error": f"HTTP error: {str(e)}"}

        except Exception as e:
            return {"error": f"Unexpected error: {str(e)}"}

def format_citations(citations: list) -> list:
    sources = []
    for citation in citations:
        references = citation.get("retrievedReferences", [])
        for ref in references:
            location = ref.get("location", {})
            s3_location = location.get("s3Location", {})
            uri = s3_location.get("uri", "")
            if uri:
                sources.append(uri)
    return sources