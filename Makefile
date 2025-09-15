.PHONY: all help agent

# Default target executed when no arguments are given to make.
all: help

######################
# HELP
######################

help:
	@echo '----'
	@echo 'agent PROMPT="..."          - run agent with prompt'
	@echo '----'

######################
# AGENT
######################

agent:
	@python scripts/agent_cli.py $(PROMPT)
