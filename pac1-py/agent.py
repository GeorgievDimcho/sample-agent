import json
import time
from functools import lru_cache
from typing import Annotated, Any, List, Literal, Union

from annotated_types import Ge, Le, MaxLen, MinLen
from google.protobuf.json_format import MessageToDict
from openai import OpenAI
from pydantic import BaseModel, Field

from connectrpc.errors import ConnectError

client = OpenAI()


class ReportTaskCompletion(BaseModel):
    tool: Literal["report_completion"]
    completed_steps_laconic: List[str]
    summary: str
    grounding_refs: List[str] = Field(default_factory=list)
    code: Literal["completed", "blocked"]


class Req_Tree(BaseModel):
    tool: Literal["tree"]
    root: str = Field("", description="tree root, empty means repository root")


class Req_Find(BaseModel):
    tool: Literal["find"]
    name: str
    root: str = "/"
    kind: Literal["all", "files", "dirs"] = "all"
    limit: Annotated[int, Ge(1), Le(20)] = 10


class Req_Search(BaseModel):
    tool: Literal["search"]
    pattern: str
    limit: Annotated[int, Ge(1), Le(20)] = 10
    root: str = "/"


class Req_List(BaseModel):
    tool: Literal["list"]
    path: str = "/"


class Req_Read(BaseModel):
    tool: Literal["read"]
    path: str


class Req_Write(BaseModel):
    tool: Literal["write"]
    path: str
    content: str


class Req_Delete(BaseModel):
    tool: Literal["delete"]
    path: str


class Req_MkDir(BaseModel):
    tool: Literal["mkdir"]
    path: str


class Req_Move(BaseModel):
    tool: Literal["move"]
    from_name: str
    to_name: str


class NextStep(BaseModel):
    current_state: str
    plan_remaining_steps_brief: Annotated[List[str], MinLen(1), MaxLen(5)] = Field(
        ...,
        description="briefly explain the next useful steps",
    )
    task_completed: bool
    # AICODE-NOTE: Keep this union aligned with the public PCM runtime surface
    # plus the local stop action. PCM currently lacks a public completion RPC, so
    # `report_completion` ends the sample loop locally and `EndTrial` still grades
    # only the runtime events that the harness persisted.
    function: Union[
        ReportTaskCompletion,
        Req_Tree,
        Req_Find,
        Req_Search,
        Req_List,
        Req_Read,
        Req_Write,
        Req_Delete,
        Req_MkDir,
        Req_Move,
    ] = Field(..., description="execute the first remaining step")


system_prompt = """
You are a pragmatic personal knowledge management assistant.

- Always start by exploring the repository root with `tree`.
- Always read `/AGENTS.md` or `/AGENTS.MD` early when it exists.
- Operate through the PCM runtime file-system tools only.
- Keep edits small and targeted.
- When you believe the task is done or blocked, use `report_completion` with a short summary and grounding refs.
- Do not invent tool results.
"""


CLI_RED = "\x1B[31m"
CLI_GREEN = "\x1B[32m"
CLI_CLR = "\x1B[0m"
CLI_BLUE = "\x1B[34m"
CLI_YELLOW = "\x1B[33m"


@lru_cache(maxsize=1)
def load_pcm_sdk() -> dict[str, Any]:
    try:
        from bitgn.vm.pcm_connect import PcmRuntimeClientSync
        from bitgn.vm.pcm_pb2 import (
            DeleteRequest,
            FindRequest,
            ListRequest,
            MkDirRequest,
            MoveRequest,
            ReadRequest,
            SearchRequest,
            TreeRequest,
            WriteRequest,
        )
    except ImportError as exc:
        # AICODE-NOTE: Keep this import lazy so the sample can fail with a clear
        # message when local Buf pins predate PCM publication instead of raising
        # an opaque import error at startup.
        raise RuntimeError(
            "Installed BitGN Python SDK does not expose `bitgn.vm.pcm_*` yet. "
            "Run `make sdk-python` from `/Users/rinat/biz/harness_core` after "
            "pushing the latest schema digest."
        ) from exc

    return {
        "PcmRuntimeClientSync": PcmRuntimeClientSync,
        "DeleteRequest": DeleteRequest,
        "FindRequest": FindRequest,
        "ListRequest": ListRequest,
        "MkDirRequest": MkDirRequest,
        "MoveRequest": MoveRequest,
        "ReadRequest": ReadRequest,
        "SearchRequest": SearchRequest,
        "TreeRequest": TreeRequest,
        "WriteRequest": WriteRequest,
    }


def call_method(target: Any, names: list[str], request: Any) -> Any:
    for name in names:
        fn = getattr(target, name, None)
        if fn is not None:
            return fn(request)
    raise AttributeError(f"Runtime client does not provide any of {names!r}")


def dispatch(vm: Any, cmd: BaseModel) -> Any:
    sdk = load_pcm_sdk()

    if isinstance(cmd, Req_Tree):
        return call_method(vm, ["tree"], sdk["TreeRequest"](root=cmd.root))
    if isinstance(cmd, Req_Find):
        return call_method(
            vm,
            ["find"],
            sdk["FindRequest"](
                root=cmd.root,
                name=cmd.name,
                type={"all": 0, "files": 1, "dirs": 2}[cmd.kind],
                limit=cmd.limit,
            ),
        )
    if isinstance(cmd, Req_Search):
        return call_method(vm, ["search"], sdk["SearchRequest"](root=cmd.root, pattern=cmd.pattern, limit=cmd.limit))
    if isinstance(cmd, Req_List):
        return call_method(vm, ["list"], sdk["ListRequest"](name=cmd.path))
    if isinstance(cmd, Req_Read):
        return call_method(vm, ["read"], sdk["ReadRequest"](path=cmd.path))
    if isinstance(cmd, Req_Write):
        return call_method(vm, ["write"], sdk["WriteRequest"](path=cmd.path, content=cmd.content))
    if isinstance(cmd, Req_Delete):
        return call_method(vm, ["delete"], sdk["DeleteRequest"](path=cmd.path))
    if isinstance(cmd, Req_MkDir):
        return call_method(vm, ["mk_dir", "mkdir"], sdk["MkDirRequest"](path=cmd.path))
    if isinstance(cmd, Req_Move):
        return call_method(vm, ["move"], sdk["MoveRequest"](from_name=cmd.from_name, to_name=cmd.to_name))
    if isinstance(cmd, ReportTaskCompletion):
        return {}

    raise ValueError(f"Unknown command: {cmd}")


def run_agent(model: str, harness_url: str, task_text: str) -> None:
    sdk = load_pcm_sdk()
    vm = sdk["PcmRuntimeClientSync"](harness_url)

    log = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": task_text},
    ]

    for i in range(30):
        step = f"step_{i + 1}"
        print(f"Next {step}... ", end="")

        started = time.time()
        resp = client.beta.chat.completions.parse(
            model=model,
            response_format=NextStep,
            messages=log,
            max_completion_tokens=16384,
        )
        elapsed_ms = int((time.time() - started) * 1000)
        job = resp.choices[0].message.parsed

        print(job.plan_remaining_steps_brief[0], f"({elapsed_ms} ms)\n  {job.function}")

        log.append(
            {
                "role": "assistant",
                "content": job.plan_remaining_steps_brief[0],
                "tool_calls": [
                    {
                        "type": "function",
                        "id": step,
                        "function": {
                            "name": job.function.__class__.__name__,
                            "arguments": job.function.model_dump_json(),
                        },
                    }
                ],
            }
        )

        try:
            result = dispatch(vm, job.function)
            txt = json.dumps(MessageToDict(result), indent=2) if result else "{}"
            print(f"{CLI_GREEN}OUT{CLI_CLR}: {txt}")
        except ConnectError as exc:
            txt = str(exc.message)
            print(f"{CLI_RED}ERR {exc.code}: {exc.message}{CLI_CLR}")

        if isinstance(job.function, ReportTaskCompletion):
            status = CLI_GREEN if job.function.code == "completed" else CLI_YELLOW
            print(f"{status}agent {job.function.code}{CLI_CLR}. Summary:")
            for item in job.function.completed_steps_laconic:
                print(f"- {item}")
            print(f"\n{CLI_BLUE}AGENT SUMMARY: {job.function.summary}{CLI_CLR}")
            if job.function.grounding_refs:
                for ref in job.function.grounding_refs:
                    print(f"- {CLI_BLUE}{ref}{CLI_CLR}")
            print(
                f"{CLI_YELLOW}PCM note:{CLI_CLR} the public PCM runtime does not expose "
                "a completion RPC yet, so this sample stops locally and `EndTrial` may "
                "still score zero until that surface lands."
            )
            break

        log.append({"role": "tool", "content": txt, "tool_call_id": step})
