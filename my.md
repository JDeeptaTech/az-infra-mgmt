```python
from typing import Callable, Optional
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI()

class APIRequest(BaseModel):
    endpoint: str
    payload: dict = {}

class APIResponse(BaseModel):
    status_code: int
    data: dict = {}

class APIHandler:
    """
    Abstract handler for API calls.
    """
    def __init__(self, successor: Optional['APIHandler'] = None):
        self._successor = successor

    def set_successor(self, successor: 'APIHandler') -> 'APIHandler':
        self._successor = successor
        return successor

    async def handle_request(self, request: APIRequest) -> Optional[APIResponse]:
        raise NotImplementedError("Subclasses must implement handle_request")

class UserAPIHandler(APIHandler):
    """
    Handles API calls related to users.
    """
    async def handle_request(self, request: APIRequest) -> Optional[APIResponse]:
        if request.endpoint.startswith("/users"):
            # Simulate calling a user management API
            print(f"UserAPIHandler: Handling request for {request.endpoint} with payload {request.payload}")
            # In a real scenario, you would make an actual API call here
            if request.endpoint == "/users" and request.payload.get("action") == "create":
                return APIResponse(status_code=201, data={"message": "User created successfully", "user_id": 123})
            elif request.endpoint == "/users/123":
                return APIResponse(status_code=200, data={"id": 123, "username": "testuser"})
            else:
                return APIResponse(status_code=404, data={"error": "User endpoint not found"})
        elif self._successor:
            return await self._successor.handle_request(request)
        return None

class ProductAPIHandler(APIHandler):
    """
    Handles API calls related to products.
    """
    async def handle_request(self, request: APIRequest) -> Optional[APIResponse]:
        if request.endpoint.startswith("/products"):
            # Simulate calling a product catalog API
            print(f"ProductAPIHandler: Handling request for {request.endpoint} with payload {request.payload}")
            # In a real scenario, you would make an actual API call here
            if request.endpoint == "/products":
                return APIResponse(status_code=200, data=[{"id": 1, "name": "Laptop"}, {"id": 2, "name": "Mouse"}])
            elif request.endpoint == "/products/1":
                return APIResponse(status_code=200, data={"id": 1, "name": "Laptop", "price": 1200})
            else:
                return APIResponse(status_code=404, data={"error": "Product endpoint not found"})
        elif self._successor:
            return await self._successor.handle_request(request)
        return None

class OrderAPIHandler(APIHandler):
    """
    Handles API calls related to orders.
    """
    async def handle_request(self, request: APIRequest) -> Optional[APIResponse]:
        if request.endpoint.startswith("/orders"):
            # Simulate calling an order management API
            print(f"OrderAPIHandler: Handling request for {request.endpoint} with payload {request.payload}")
            # In a real scenario, you would make an actual API call here
            if request.endpoint == "/orders" and request.payload.get("action") == "create":
                return APIResponse(status_code=201, data={"message": "Order created successfully", "order_id": 456})
            elif request.endpoint == "/orders/456":
                return APIResponse(status_code=200, data={"id": 456, "items": [1, 2], "total": 1500})
            else:
                return APIResponse(status_code=404, data={"error": "Order endpoint not found"})
        elif self._successor:
            return await self._successor.handle_request(request)
        return None

# Create the chain of responsibility
user_handler = UserAPIHandler()
product_handler = ProductAPIHandler()
order_handler = OrderAPIHandler()

user_handler.set_successor(product_handler).set_successor(order_handler)

async def invoke_api(request: APIRequest) -> APIResponse:
    """
    Invokes the appropriate API based on the request using the chain of responsibility.
    """
    response = await user_handler.handle_request(request)
    if response:
        return response
    else:
        raise HTTPException(status_code=404, detail="Endpoint not found")

@app.post("/invoke")
async def invoke(api_request: APIRequest):
    return await invoke_api(api_request)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
```
