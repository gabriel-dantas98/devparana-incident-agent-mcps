import os
import sys
import discord
from dotenv import load_dotenv
from collections import defaultdict
from typing import Dict, List, Tuple
from rich import print as rich_print
from langfuse.langchain import CallbackHandler

# Ensure local execution can import the `agent` package from src/
CURRENT_DIR = os.path.dirname(__file__)
REPO_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))
SRC_DIR = os.path.join(REPO_ROOT, "src")
for _p in (SRC_DIR, REPO_ROOT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from agent import graph

load_dotenv()

langfuse_handler = CallbackHandler()
intents = discord.Intents.default()
intents.message_content = True

DISCORD_MAX_MESSAGE_LENGTH = 2000

def split_message_into_chunks(message: str, max_length: int = DISCORD_MAX_MESSAGE_LENGTH) -> List[str]:
    """
    Split a message into chunks respecting Discord's character limit.
    Prioritizes splitting by newlines and markdown headers (#).
    """
    print("Message length: ", len(message))
    rich_print("========Rich printing message=========")
    rich_print(message)

    if len(message) <= max_length:
        return [message]
    
    chunks = []
    current_chunk = ""
    
    # Split by newlines first, then by # for markdown headers
    lines = message.split('\n')
    
    for line in lines:
        # If adding this line would exceed the limit
        if len(current_chunk) + len(line) + 1 > max_length:
            # If current chunk is not empty, save it
            if current_chunk.strip():
                chunks.append(current_chunk.strip())
                current_chunk = ""
            
            # If the line itself is too long, split it by # markers
            if len(line) > max_length:
                parts = line.split('#')
                temp_line = ""
                
                for i, part in enumerate(parts):
                    prefix = '#' if i > 0 else ''
                    test_addition = prefix + part
                    
                    if len(temp_line) + len(test_addition) > max_length:
                        if temp_line.strip():
                            chunks.append(temp_line.strip())
                        temp_line = test_addition
                    else:
                        temp_line += test_addition
                
                if temp_line.strip():
                    current_chunk = temp_line
            else:
                current_chunk = line
        else:
            # Add line to current chunk
            if current_chunk:
                current_chunk += '\n' + line
            else:
                current_chunk = line
    
    # Don't forget the last chunk
    if current_chunk.strip():
        chunks.append(current_chunk.strip())
    
    # Fallback: if any chunk is still too long, force split it
    final_chunks = []
    for chunk in chunks:
        if len(chunk) <= max_length:
            final_chunks.append(chunk)
        else:
            # Force split by character count as last resort
            while len(chunk) > max_length:
                final_chunks.append(chunk[:max_length])
                chunk = chunk[max_length:]
            if chunk:
                final_chunks.append(chunk)
    
    return final_chunks

class VibeDebuggerDiscordClient(discord.Client):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.conversation_by_channel: Dict[int, List[Tuple[str, str]]] = defaultdict(list)

    async def on_ready(self):
        print('Logged in as')
        print(self.user.name)
        print(self.user.id)
        print('------')

    async def on_message(self, message):
        print(f'Message from {message.author}: {message.content}')
        
        # we do not want the bot to reply to itself
        if message.author.id == self.user.id:
            return

        channel_history = self.conversation_by_channel[message.channel.id]
        channel_history.append(("user", message.content or ""))

        # Send the accumulated conversation to the agent and reply with its answer
        try:
            result = await graph.ainvoke({
                "messages": channel_history
            }, config={"callbacks": [langfuse_handler]})

            # Extract the latest assistant message content
            messages = result.get("messages", [])
            reply_content = None
            if messages:
                last_msg = messages[-1]
                reply_content = getattr(last_msg, "content", None)

            if not reply_content:
                reply_content = "(no response)"
        except Exception as e:
            reply_content = f"Agent error: {e}"

        # Track assistant response in history
        channel_history.append(("assistant", reply_content))

        # Split message into chunks and send each one
        chunks = split_message_into_chunks(reply_content or "")
        for chunk in chunks:
            if chunk.strip():  # Only send non-empty chunks
                await message.channel.send(chunk)

client = VibeDebuggerDiscordClient(intents=intents)
client.run(os.getenv('DISCORD_TOKEN') or os.getenv('DISCORD_PUBLIC_KEY'))
