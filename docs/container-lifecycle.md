# Container Lifecycle Overview

![Beets Container Lifecycle](container-lifecycle.svg)

This diagram highlights when each build argument or runtime environment variable influences dependency installation during the image build and container startup sequence.

### Source

```mermaid
flowchart TD
    A1["Build Args<br/>PYTHON_VERSION<br/>PYTHON_BASE_SUFFIX"] --> B0
    A2["Build Arg<br/>APK_BUILD_DEPS"] --> B1
    A3["Build Args<br/>BEETS_REF<br/>DEFAULT_PIP_SOURCES<br/>DEFAULT_PIP_PACKAGES<br/>USER_PIP_PACKAGES"] --> B2
    A4["Build Arg<br/>APK_RUNTIME_EXTRAS"] --> R1
    A5["Build Args<br/>DEFAULT_PIP_PACKAGES<br/>USER_PIP_PACKAGES"] --> R2
    A6["Env. Vars<br/>PUID<br/>PGID<br/>UMASK"] --> E1
    A7["Env. Vars<br/>RUNTIME_APK_PACKAGES<br/>RUNTIME_PIP_PACKAGES"] --> E2

    subgraph Docker Build
        direction LR
        subgraph Builder Stage
            B0["Select Python Base Image"] --> B1
            B1["apk add build deps<br/>+ APK_BUILD_DEPS"] --> B2
            B2["pip wheel into /wheels:<br/>beets, default srcs + pkgs<br/>+ USER_PIP_PACKAGES"]
        end

        subgraph Runtime Stage
            B2 --> R1["apk add runtime deps:<br/>ffmpeg, chromaprint, imagemagick, ...<br/>+ APK_RUNTIME_EXTRAS"]
            R1 --> R2["pip install from wheels:<br/>beets, default pkgs<br/>+ USER_PIP_PACKAGES"]
            R2 --> R3["Copy entry scripts & licenses"]
        end
    end

    subgraph Container Start
        direction TB
        R3 --> E1["docker-entrypoint.sh<br/>Sets up user/group and file mask"]
        E1 --> E2["Runtime Installs - <b>Discouraged</b><br/>apk add / pip install on <b>every start</b> of:<br/>RUNTIME_APK_PACKAGES<br/>RUNTIME_PIP_PACKAGES"]
        E2 --> E3["Issued command<br/>or start-web.sh"]
    end
```
