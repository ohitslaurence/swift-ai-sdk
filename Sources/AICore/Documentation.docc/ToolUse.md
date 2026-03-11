# Tool Use

Define tools, run multi-step execution loops, and build reusable agents.

## Overview

The SDK supports tool-calling workflows where the model decides which tools to
invoke. Tools are defined once and work across all providers that advertise
tool support via ``AIToolCapabilities``.

## Defining a tool

Create an ``AITool`` with a name, description, JSON Schema for the input, and a
handler closure:

```swift
let weatherTool = AITool(
    name: "get_weather",
    description: "Get the current weather for a city",
    inputSchema: .object(
        properties: ["city": .string(description: "The city name")],
        required: ["city"]
    ),
    handler: { input in
        // input is raw Data — decode as needed
        "22°C, sunny"
    }
)
```

For strongly-typed tools, use ``AITool/define(name:description:needsApproval:handler:)``:

```swift
struct WeatherInput: AIStructured {
    let city: String
}

struct WeatherOutput: Encodable, Sendable {
    let temperature: String
    let condition: String
}

let weatherTool = try AITool.define(
    name: "get_weather",
    description: "Get the current weather for a city",
    handler: { (input: WeatherInput) -> WeatherOutput in
        WeatherOutput(temperature: "22°C", condition: "sunny")
    }
)
```

## Single-step tool calls

Pass tools in the request and inspect the response for tool use content:

```swift
let response = try await provider.complete(
    AIRequest(
        model: .gpt(.gpt5Mini),
        messages: [.user("What's the weather in London?")],
        tools: [weatherTool]
    )
)
```

## Multi-step tool loops

Use ``AIProvider/completeWithTools(_:stopWhen:approvalHandler:toolCallRepairHandler:onStepComplete:)``
to let the SDK execute tools and feed results back automatically:

```swift
let result = try await provider.completeWithTools(
    AIRequest(
        model: .gpt(.gpt5Mini),
        messages: [.user("What's the weather in London and Paris?")],
        tools: [weatherTool]
    ),
    stopWhen: [.maxSteps(5)]
)

print(result.response.text)
print("Steps: \(result.steps.count)")
print("Total tokens: \(result.totalUsage.totalTokens)")
```

### Stop conditions

Control when the loop ends with ``StopCondition``:

- `.maxSteps(n)` — Stop after `n` tool execution rounds.
- `.toolCalled(name)` — Stop after a specific tool is called.
- Custom conditions via closure.

Multiple conditions combine with OR logic — the loop stops when any condition
is met.

### Streaming tool loops

Use ``AIProvider/streamWithTools(_:stopWhen:approvalHandler:toolCallRepairHandler:onStepComplete:)``
for streamed tool execution:

```swift
let toolStream = provider.streamWithTools(
    AIRequest(
        model: .gpt(.gpt5Mini),
        messages: [.user("Research this topic")],
        tools: [searchTool, summarizeTool]
    )
)

for try await event in toolStream {
    // Events from each step are stitched into a single stream
}
```

## Approval-gated tools

Mark a tool as requiring approval to add a human-in-the-loop gate:

```swift
let deleteTool = AITool(
    name: "delete_record",
    description: "Delete a database record",
    inputSchema: .object(
        properties: ["id": .string(description: "Record ID")],
        required: ["id"]
    ),
    needsApproval: true,
    handler: { input in "Deleted" }
)

let result = try await provider.completeWithTools(
    request,
    approvalHandler: { toolUse in
        // Return true to allow, false to deny
        print("Approve \(toolUse.name)?")
        return true
    }
)
```

`toolCallRepairHandler` is used for typed tool input decode failures. It lets you
repair malformed JSON locally and retry the decode once without forcing an extra
model round-trip.

## Agents

``Agent`` wraps provider, model, tools, and stop conditions into a reusable
callable unit:

```swift
let agent = Agent(
    provider: provider,
    model: .gpt(.gpt5Mini),
    systemPrompt: "You are a helpful assistant.",
    tools: [weatherTool, searchTool],
    stopConditions: [.maxSteps(10)]
)

// Non-streaming
let result = try await agent.run("What's the weather in London?")

// Streaming
let stream = agent.stream("Research quantum computing")
for try await event in stream {
    // ...
}
```
