import os
import sys
import discord
from dotenv import load_dotenv
from collections import defaultdict
from typing import Dict, List, Tuple

# Ensure local execution can import the `agent` package from src/
CURRENT_DIR = os.path.dirname(__file__)
REPO_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))
SRC_DIR = os.path.join(REPO_ROOT, "src")
for _p in (SRC_DIR, REPO_ROOT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

from agent import graph

load_dotenv()

intents = discord.Intents.default()
intents.message_content = True

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
            })

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

        # Discord hard limit is 2000 chars
        await message.channel.send((reply_content or "")[0:1900])

client = VibeDebuggerDiscordClient(intents=intents)
client.run(os.getenv('DISCORD_TOKEN') or os.getenv('DISCORD_PUBLIC_KEY'))
