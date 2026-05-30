"""
agent.py
--------
The "brain" of Open Julius.

Wraps the Gemini API (Google AI Studio) and runs an agentic loop that is the
heart of any Julius-style tool:

    user question
        -> Gemini writes Python code
        -> we run it (executor.py)
        -> Gemini sees stdout / charts / errors
        -> Gemini fixes & iterates if needed
        -> Gemini writes a plain-language answer with the insights

Gemini drives the loop using a single tool, `run_python`, via function calling.
"""

import os
import re
import time

from google import genai
from google.genai import types

from executor import execute_code


MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
MAX_TURNS = int(os.getenv("MAX_AGENT_TURNS", "12"))

# How many times to automatically retry when we hit the free-tier rate limit.
MAX_RETRIES = int(os.getenv("MAX_RETRIES", "4"))


def _retry_delay_seconds(err: Exception, attempt: int) -> float:
    """Decide how long to wait before retrying a rate-limited request.

    Gemini's 429 error usually suggests a delay like "retry in 22s"; honor it
    when present, otherwise fall back to exponential backoff (2, 4, 8, ...).
    """
    text = str(err)
    match = re.search(r"retry(?:Delay)?['\":\s]*(?:in\s+)?(\d+(?:\.\d+)?)\s*s", text)
    if match:
        return min(float(match.group(1)) + 1.0, 60.0)
    return min(2 ** attempt, 30.0)


def _is_rate_limit(err: Exception) -> bool:
    text = str(err)
    return "429" in text or "RESOURCE_EXHAUSTED" in text


def _generate_with_retry(client, contents, config):
    """Call generate_content, automatically waiting out free-tier 429 limits."""
    last_err = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            return client.models.generate_content(
                model=MODEL, contents=contents, config=config
            )
        except Exception as err:  # noqa: BLE001
            last_err = err
            if _is_rate_limit(err) and attempt < MAX_RETRIES:
                wait = _retry_delay_seconds(err, attempt)
                print(f"[Open Julius] Rate limited; retrying in {wait:.0f}s "
                      f"(attempt {attempt}/{MAX_RETRIES})...")
                time.sleep(wait)
                continue
            raise
    raise last_err


SYSTEM_PROMPT = """You are Open Julius, an expert AI data analyst. \
You help users understand their data by writing and running Python code, \
then explaining the results in clear, plain language.

HOW YOU WORK:
- Use the `run_python` tool to execute Python for ALL data work: exploring, \
cleaning, computing statistics, modelling, and making charts. Never invent \
numbers - always compute them from the data.
- These libraries are ready in the environment: pandas as `pd`, numpy as `np`, \
matplotlib.pyplot as `plt`, and seaborn as `sns`. scikit-learn, scipy and \
statsmodels are installed and can be imported when needed.
- The user's uploaded data is preloaded as the DataFrame variable(s) described \
below. Use those exact variable names.
- Variables persist between your `run_python` calls within this conversation, \
so you can build on earlier results like a notebook.
- When a visualization helps, create it with matplotlib/seaborn. Give every \
chart a clear title and axis labels. Create one figure per chart. \
Do NOT call plt.show() and do NOT call plt.savefig() - figures are captured \
automatically and shown to the user.
- Print the intermediate results you need to reason about, e.g. \
print(df.describe()) or print(result.head()).
- If a run_python call returns an ERROR, read it carefully and fix the code in \
your next run_python call. Do not give up after one error.
- Work step by step: if you are unsure about the data, inspect it first, then \
do the requested analysis.

YOUR FINAL ANSWER:
- After the analysis, reply to the user in clear markdown with the key \
findings and the actual numbers you computed.
- Be concise and insightful, like a senior data analyst summarizing for a \
colleague. Do NOT paste large blocks of code in the final answer - the code \
and its outputs are already shown to the user separately.
"""


# ---- Tool definition -------------------------------------------------------

RUN_PYTHON_TOOL = types.Tool(
    function_declarations=[
        types.FunctionDeclaration(
            name="run_python",
            description=(
                "Execute Python code for data analysis and visualization. "
                "The user's data is available as the DataFrame variable(s) "
                "given in the system context. pd, np, plt, sns are preloaded. "
                "Returns the code's stdout, whether any charts were created, "
                "and any error traceback. Variables persist across calls."
            ),
            parameters=types.Schema(
                type=types.Type.OBJECT,
                properties={
                    "code": types.Schema(
                        type=types.Type.STRING,
                        description="The Python code to execute.",
                    ),
                },
                required=["code"],
            ),
        )
    ]
)


def build_client() -> genai.Client:
    """Create a Gemini client from the GEMINI_API_KEY env var."""
    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise RuntimeError(
            "GEMINI_API_KEY is not set. Copy backend/.env.example to "
            "backend/.env and add your Google AI Studio key."
        )
    return genai.Client(api_key=api_key)


def _make_config(dataset_context: str) -> types.GenerateContentConfig:
    system = SYSTEM_PROMPT
    if dataset_context:
        system += "\n\n--- LOADED DATA ---\n" + dataset_context
    else:
        system += (
            "\n\nNOTE: No data has been uploaded yet. If the user asks about "
            "data, politely ask them to upload a CSV or Excel file first."
        )
    return types.GenerateContentConfig(
        system_instruction=system,
        tools=[RUN_PYTHON_TOOL],
        temperature=0.2,
        # We execute the tool ourselves, so disable the SDK's auto-calling.
        automatic_function_calling=types.AutomaticFunctionCallingConfig(
            disable=True
        ),
    )


def _result_for_model(result: dict) -> str:
    """Turn an execution result into the text the model sees next turn."""
    parts = []
    if result.get("stdout"):
        parts.append("STDOUT:\n" + result["stdout"])
    if result.get("charts"):
        n = len(result["charts"])
        parts.append(f"[{n} chart(s) were generated and shown to the user.]")
    if result.get("error"):
        parts.append("ERROR (fix this in your next run_python call):\n"
                     + result["error"])
    if not parts:
        parts.append("Code ran successfully with no printed output.")
    return "\n\n".join(parts)


def run_agent(client, contents, namespace, dataset_context):
    """Run the full agentic loop for one user message.

    Args:
        client:          genai.Client
        contents:        the running conversation history (list of Content);
                         the latest user message must already be appended.
                         This list is mutated in place so history persists.
        namespace:       the per-session execution namespace (dict).
        dataset_context: text description of the loaded DataFrame(s).

    Returns:
        {
          "answer": str,            # final natural-language reply (markdown)
          "steps": [                # each code execution, in order
            {"code", "stdout", "charts": [b64...], "error"}
          ],
        }
    """
    config = _make_config(dataset_context)
    steps = []
    final_text = ""

    for _ in range(MAX_TURNS):
        response = _generate_with_retry(client, contents, config)

        if not response.candidates:
            final_text = final_text or "I couldn't generate a response. Please try again."
            break

        candidate = response.candidates[0]
        content = candidate.content
        if content is None or not content.parts:
            break

        # Record the model's turn in history.
        contents.append(content)

        # Separate any text and any function calls from this turn.
        function_calls = []
        for part in content.parts:
            if getattr(part, "text", None):
                final_text = part.text.strip()
            if getattr(part, "function_call", None):
                function_calls.append(part.function_call)

        # No tool call -> the model produced its final answer.
        if not function_calls:
            break

        # Execute each requested tool call and gather responses into ONE
        # Content (the API expects responses to match the calls in order).
        response_parts = []
        for fc in function_calls:
            if fc.name == "run_python":
                code = ""
                if fc.args:
                    code = fc.args.get("code", "") or ""
                result = execute_code(code, namespace)
                steps.append({
                    "code": code,
                    "stdout": result["stdout"],
                    "charts": result["charts"],
                    "error": result["error"],
                })
                model_view = _result_for_model(result)
            else:
                model_view = f"Unknown tool '{fc.name}'."

            response_parts.append(
                types.Part.from_function_response(
                    name=fc.name,
                    response={"result": model_view},
                )
            )

        contents.append(types.Content(role="user", parts=response_parts))
    else:
        # Loop exhausted without a final text answer.
        if not final_text:
            final_text = (
                "I reached the maximum number of analysis steps. "
                "Here is what I have so far - feel free to ask a follow-up."
            )

    return {"answer": final_text, "steps": steps}
