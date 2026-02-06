# Veris Skills

A collection of skills for coding agents that take advantage of the [Veris AI](https://veris.ai) simulation platform.

## Installation

Add skills to your Claude Code configuration:

```bash
git clone git@github.com:veris-ai/veris-skills.git ~/.claude/skills/veris-skills
```

## Available Skills

### `/grader-generator`

Generate failure-mode graders for evaluating AI agents. Given an agent's source code, creates a comprehensive multi-layer grader with atomic checks organized by category.

- Analyzes agent capabilities, tools, and business rules
- Creates atomic checks that test ONE failure mode each
- Outputs for Veris platform and OpenAI Evals API

```
/grader-generator path/to/agent/source
```

## License

Apache 2.0
