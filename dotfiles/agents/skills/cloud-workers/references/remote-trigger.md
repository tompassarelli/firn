# RemoteTrigger routine schema


```json
{"name": "<repo>-cloud-worker", "run_once_at": "<far future>", "enabled": true,
 "job_config": {"ccr": {
   "environment_id": "env_01EkrXafT5PjQN9jUWzwMhLd",
   "session_context": {"model": "claude-opus-5-5",
     "sources": [{"git_repository": {"url": "https://github.com/tompassarelli/<repo>"}}],
     "allowed_tools": ["..."]},
   "events": [{"data": {"uuid": "<fresh v4>", "session_id": "", "type": "user",
     "parent_tool_use_id": null,
     "message": {"role": "user", "content": "<PROMPT>"}}}]}}}
```


Existing Wisp routine: `trig_01Rv4YsBNXztmR2bKGs4bsth`; Default environment: `env_01EkrXafT5PjQN9jUWzwMhLd`.
