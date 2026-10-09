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


Smashcraft routine: `trig_01RoHaKMjMDSpHAouCU3FkmU`; environment `env_01MLPz6krPVjM4pH3YGTpQz3` (named Smashcraft; an API-created routine needs one save in the web editor to bind it). Send each update and its run as separate sequential calls; a run sent in parallel with its update fires the previous prompt.
