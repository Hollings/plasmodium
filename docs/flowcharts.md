# Plasmodium Flowcharts

## System Flow

Task lifecycle from creation to completion.

```mermaid
flowchart TD
    subgraph User
        A[pm task 'description']
    end

    subgraph Owner["Owner Agent"]
        B[Spawn & read task]
        C[Create phase]
        D[Define perspectives]
        E[Spawn phase agents]
        F{More phases<br/>needed?}
        G[Task complete]
    end

    subgraph Phase["Phase (bounded discussion)"]
        H[Agent A<br/>perspective 1]
        I[Agent B<br/>perspective 2]
        J[Discussion + Work]
        K[Message limit reached<br/>+ all work done]
    end

    A --> B
    B --> C
    C --> D
    D --> E
    E --> H & I
    H & I --> J
    J --> K
    K --> F
    F -->|Yes| C
    F -->|No| G

    style A fill:#238636,stroke:#2ea043,color:#fff
    style G fill:#238636,stroke:#2ea043,color:#fff
    style B fill:#8957e5,stroke:#a371f7,color:#fff
    style C fill:#8957e5,stroke:#a371f7,color:#fff
    style D fill:#8957e5,stroke:#a371f7,color:#fff
    style E fill:#8957e5,stroke:#a371f7,color:#fff
    style F fill:#8957e5,stroke:#a371f7,color:#fff
    style H fill:#9e6a03,stroke:#d29922,color:#fff
    style I fill:#9e6a03,stroke:#d29922,color:#fff
    style J fill:#1f6feb,stroke:#58a6ff,color:#fff
    style K fill:#1f6feb,stroke:#58a6ff,color:#fff
```

## Phase Agent Flow

Decision loop for agents within a phase.

```mermaid
flowchart TD
    A([Agent spawned<br/>with perspective]) --> B[pm chat<br/>read messages]
    B --> C{Phase<br/>closed?}
    C -->|Yes| D([Exit])
    C -->|No| E{Need to<br/>build?}

    E -->|No| F[pm say '...'<br/>share perspective]
    F --> B

    E -->|Yes| G[pm say 'plan...'<br/>discuss first]
    G --> H[pm work '...'<br/>claim work item]
    H --> I[Build / Code<br/>do the work]
    I --> J[pm work-done<br/>mark complete]
    J --> B

    style A fill:#238636,stroke:#2ea043,color:#fff
    style D fill:#da3633,stroke:#f85149,color:#fff
    style C fill:#1f6feb,stroke:#58a6ff,color:#fff
    style E fill:#1f6feb,stroke:#58a6ff,color:#fff
    style H fill:#9e6a03,stroke:#d29922,color:#fff
    style J fill:#9e6a03,stroke:#d29922,color:#fff
```

## Legend

| Color | Meaning |
|-------|---------|
| 🟢 Green | Start/End |
| 🟣 Purple | Owner actions |
| 🔵 Blue | Decisions / Phase |
| 🟠 Orange | Work items / Phase agents |
| ⬛ Gray | Actions |
