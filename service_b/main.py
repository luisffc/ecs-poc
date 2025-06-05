import httpx
from fastapi import FastAPI
from fastapi.responses import JSONResponse
import os

# Core URL where Service A is available
SERVICE_A_URL = os.environ.get("SERVICE_A_URL")


app = FastAPI(
    title="Service B FastAPI Client",
    version="0.1.0",
)


@app.get("/ping_service_a")
def ping_service_a() -> JSONResponse:
    with httpx.Client() as client:
        response_from_a = client.get(f"{SERVICE_A_URL}/ping")

        response = f"{response_from_a.json()['message']} (via Service B)"

        return JSONResponse({
            "message": response
        })
