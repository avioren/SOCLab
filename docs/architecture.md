# Architecture

```text
Endpoint / test telemetry
        |
        v
   Wazuh Manager
        |
        v
   Wazuh Indexer
        |
        +----> Wazuh Dashboard
        |
        v
      Alert
        |
        v
     Shuffle
        |
        v
Enrichment / response
```

The Git repository contains our automation, tests, documentation, and future Detection-as-Code content. Wazuh and Shuffle themselves are cloned as runtime dependencies into `/opt/soclab`; their upstream source trees are not vendored into this repository.

Future Detection-as-Code work should live under `detections/`, with generated target artifacts treated as disposable build outputs.
