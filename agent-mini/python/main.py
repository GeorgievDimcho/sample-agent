from harness.agent_mini.agent_mini_connect import AgentMiniHarnessClientSync
from platform.benchmark.benchmark_connect import BenchmarkServiceClientSync


def main():
    print("Hello from python!")

    client = BenchmarkServiceClientSync(address="http://127.0.0.1:8080")

    harness = AgentMiniHarnessClientSync(address="http://127.0.0.1:8080")



if __name__ == "__main__":
    main()
