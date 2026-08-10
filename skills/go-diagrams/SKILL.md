---
name: go-diagrams
description: Generate system architecture diagrams using the Go go-diagrams library. Outputs DOT files rendered to PNG via Graphviz. Best for infrastructure, microservices, and network topology diagrams.
---

# GO-Diagrams Skill

The `go-diagrams` library (github.com/blushft/go-diagrams) creates architecture diagrams in Go.

## Setup
```bash
go install github.com/blushft/go-diagrams@latest
# Also requires Graphviz for rendering
```

## Basic Example

Create a file `diagram.go`:
```go
package main

import (
    "github.com/blushft/go-diagrams/diagram"
    "github.com/blushft/go-diagrams/nodes/apps"
    "github.com/blushft/go-diagrams/nodes/gcp"
)

func main() {
    d, _ := diagram.New(diagram.Filename("ai-stack"), diagram.Label("AI Creator Stack"))

    claude := apps.ML.Pytorch("Claude Code")
    n8n    := apps.Network.Internet("n8n")
    ghost  := apps.Network.Internet("Ghost Blog")

    d.Connect(claude, n8n)
    d.Connect(claude, ghost)
    d.Render()
}
```

```bash
go run diagram.go
# Outputs: ai-stack.png
```

## Microservices Example
```go
package main

import (
    "github.com/blushft/go-diagrams/diagram"
    "github.com/blushft/go-diagrams/nodes/apps"
    "github.com/blushft/go-diagrams/nodes/aws"
)

func main() {
    d, _ := diagram.New(diagram.Filename("microservices"), diagram.Label("Video Pipeline"))

    intake   := apps.Network.Internet("API Gateway")
    ingest   := aws.Compute.Lambda("Ingest Service")
    render   := aws.Compute.Lambda("Render Service")
    publish  := aws.Compute.Lambda("Publish Service")
    storage  := aws.Storage.S3("Media Store")
    queue    := aws.Integration.Sqs("Job Queue")

    d.Connect(intake, ingest)
    d.Connect(ingest, queue)
    d.Connect(queue, render)
    d.Connect(render, storage)
    d.Connect(storage, publish)
    d.Render()
}
```

## Workflow
1. Understand the system/infrastructure the user wants to diagram
2. Write the Go code
3. Run: `go run diagram.go`
4. The PNG renders automatically via Graphviz
5. Show the user the result and iterate

## Note
If go-diagrams is not installed, generate the equivalent Python diagrams or Mermaid code instead as a fallback — both achieve the same visual result.
