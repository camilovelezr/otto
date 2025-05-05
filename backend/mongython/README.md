# Mongython Backend 🐍⚙️ MongoDB

Hey there, adventurer! Welcome to the engine room of Otto – the `mongython` backend.

## 🤔 So, What IS This Thing?

This is the Python powerhouse behind the slick Otto app you know and love. Built with FastAPI, it's the crucial link handling all the serious business: talking to databases, managing users, orchestrating AI chats, and keeping your secrets safe.

Think of it as the trusty stage crew making the magic happen behind the curtains. ✨

Here's the tech cocktail:

*   **FastAPI:** For building the API endpoints faster than you can say "asynchronous".
*   **MongoDB:** Our database of choice, managed with the lovely **Beanie ODM**. 🗄️
*   **LiteLLM:** The secret sauce that lets Otto chat with *all sorts* of AI models (OpenAI, Gemini, Anthropic, local ones... you name it!). 🤯
*   **Uvicorn:** Serving it all up hot and fresh. 🔥
*   **Top-Notch Encryption:** Using battle-tested libraries to keep conversations end-to-end encrypted. 🔒

## 🚀 Core Features

*   **User Management:** Handles registration, login, and all that jazz.
*   **Conversation CRUD:** Creates, reads, updates, and deletes your chat histories securely.
*   **LLM Model Management:** Keeps track of available AI models and their configurations.
*   **Chat Proxy:** Securely streams responses between the Otto app and the selected LLM via LiteLLM. 💬
*   **Health Checks:** `/` and `/health` endpoints to make sure everything's ticking along nicely. ✅
*   **Encryption Utilities:** Does the heavy lifting for securing data.

## 🎉 Getting It Running

Want to fire up this backend beast?

1.  **Navigate Here:**
    ```bash
    cd backend/mongython
    ```
2.  **Set Up a Virtual Environment with UV:** (Faster than a speeding bullet! ⚡ If you don't have uv, install it first: `curl -LsSf https://astral.sh/uv/install.sh | sh` or `pip install uv`)
    ```bash
    uv venv .venv # Creates a venv named .venv
    source .venv/bin/activate # On Linux/macOS
    # .\.venv\Scripts\activate # On Windows
    ```
3.  **Install Dependencies with UV:** (All dependencies are defined in pyproject.toml and locked in uv.lock)
    ```bash
    uv sync # This will install everything needed based on pyproject.toml/uv.lock
    ```
4.  **Environment Variables:** This is CRUCIAL. You'll need a `.env` file in the `backend/mongython` directory. You can copy `.env.sample` to `.env` and modify it:
    ```bash
    cp .env.sample .env
    ```
    Make sure these variables are set correctly in your `.env`:
    *   `MONGO_URI`: Your MongoDB connection string (e.g., `mongodb://localhost:27017`).
    *   `LITELLM_URL`: Where your LiteLLM proxy is running (e.g., `http://localhost:4000`).
    *   `LITELLM_MASTER_KEY`: Your master key for authenticating with LiteLLM if needed (e.g., `sk-0000`).
    *   *(Check `src/mongython/api/app.py` or other config spots for potentially more env vars you might need depending on your setup!)*
5.  **Run LiteLLM:** You need LiteLLM running separately to handle the AI model connections. Follow the [LiteLLM Proxy Quick Start guide](https://docs.litellm.ai/docs/#quick-start-proxy---cli) for setup instructions.
6.  **Start the Server:** (Make sure your uv-managed venv is active!)
    ```bash
    # Use the script defined in pyproject.toml via uv run (prettier!)
    uv run mongython serve --reload
    ```
    *Alternatively, use uvicorn directly:*
    ```bash
    uvicorn mongython.api:app --host 0.0.0.0 --port 8088 --reload
    ```

Now you should have the Mongython API running locally, probably on `http://localhost:8088`. Go build something awesome! 🚀
