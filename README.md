# docker-beets

Packages the upstream [`beetbox/beets`](https://github.com/beetbox/beets)
music manager on a Alpine base, optional build extras, and an entrypoint that
handles UID/GID mapping at runtime. Images published to Docker Hub and GHCR.

## Available Images

- [GHCR](https://github.com/treyturner/docker-beets/pkgs/container/beets): `ghcr.io/treyturner/beets`
- [Docker Hub](https://hub.docker.com/r/treyturner/beets): `docker.io/treyturner/beets`

### Tag Strategy

- `vX.Y.Z` - manual builds that pin the upstream beets release tag (e.g. `v2.5.1`)
  - You want one of these. They **ARE** mutable, but always contain the specified version of beets.
  - Need a version not currently posted? Open an issue and I'd be happy to build and publish it.
- `latest` - the latest version of beets that I manually promoted after deeming it stable (YMMV)
  - **Discouraged**, but provided for convenience if you don't require a specific version of beets

  - ⚠️ If you use this tag, pull, and recreate your container, you **WILL** eventually upgrade beets to a version that breaks one or more plugins and/or config 😭

- `vX.Y.Z-dev` - latest dev image for beets X.Y.Z
  - Where builds of upstream refs are tested before being manually promoted to `vX.Y.Z`
  - Automatically built for the version of beets pinned in [`build-and-publish-dev.yaml`](.github/workflows/build-and-publish-dev.yaml) on merges to this repo's `main` branch
- `vX.Y.Z-dev-<run_id>.<attempt_id>` – build-specific dev images for traceability
  - For debugging only, ie. helping me understand an issue you've reported

## Bundled Packages

### Beets + plugins:

- `beets[discogs,beatport]`
- `beets-beatport4` (bundled only for beets `v2.3.x`)
- `beets-filetote` (bundled only for beets `v2.3.x`)
- `git+https://github.com/edgars-supe/beets-importreplace.git`

### Python packages:

- `requests`
- `requests_oauthlib`
- `beautifulsoup4`
- `pyacoustid`
- `pylast`
- `langdetect`
- `flask`
- `Pillow`

### Runtime tools

- `ffmpeg`
- `chromaprint` (provides `fpcalc` required by the `chroma` plugin)
- `jq`
- `yq`

## Usage

### Environment variables

|       Variable        |                           Description                          |  Default  |
| :-------------------: | :------------------------------------------------------------: | :-------: |
|        `PUID`         |          Numeric user ID that the entrypoint creates           |   `99`    |
|        `PGID`         |          Numeric group ID that the entrypoint creates          |   `100`   |
|        `UMASK`        |                Mask applied before spawning beets              |  `0002`   |
|      `BEETSDIR`       |                     Path to the beets config                   | `/config` |
| `RUNTIME_APK_PACKAGES`| Space-separated list of Alpine packages to install at runtime  |  *(none)* |
| `RUNTIME_PIP_PACKAGES`| Space-separated list of Python packages to install at runtime  |  *(none)* |

### Bind mounts

| Container Path |                             Description                             |
| :------------: | :-----------------------------------------------------------------: |
|   `/config`    |  Beets configuration (`config.yaml`), state, and plugin artifacts   |
|   *(custom)*   | Library mount(s) of your choice, e.g. `-v /mnt/user/music:/library` |

### Running one-off commands

The container is suited for one-off commands; simply put it after the image name:

```bash
$ docker run --rm \
  -v "$(pwd)/config:/config" \
  -v "$(pwd)/library:/library" \
  ghcr.io/treyturner/beets:v2.5.1 \
  beet --version

beets version 2.5.1
```

### Interactive shell

The image ships with `bash` if you prefer to work with an interactive shell inside the container:

```bash
$ docker run --rm -it \
  -v "$(pwd)/config:/config" \
  -v "$(pwd)/library:/library" \
  ghcr.io/treyturner/beets:v2.5.1 \
  bash

b8afc450904c:/config$ beet --version
beets version 2.5.1
```

### Persisting a container

The default command launches the [`web` plugin](https://beets.readthedocs.io/en/stable/plugins/web.html)'s HTTP server. If no config exists, the entrypoint creates one with `web.host: 0.0.0.0` (required to reach the web UI from outside the container); otherwise it will **MODIFY** your config before starting the server by enabling the `web` plugin and ensuring the host binding is present.

```bash
$ docker run -d --rm --name beets \
  -p 8337:8337 \
  -v "$(pwd)/config:/config" \
  -v "$(pwd)/library:/library" \
  ghcr.io/treyturner/beets:v2.5.1

$ docker logs beets
 * Serving Flask app 'beetsplug.web'
 * Debug mode: off
WARNING: This is a development server. Do not use it in a production deployment. Use a production WSGI server instead.
 * Running on http://127.0.0.1:8337
Press CTRL+C to quit
```

Once started, you can access the UI at `http://ip.of.docker.host:8337`, or start a shell via:

```
$ docker exec -it beets bash
2edbccf027b4:/config# beet --version
beets version 2.3.1
```

### Installing additional packages at runtime

You can install additional Alpine (apk) or Python (pip) packages at container startup using the `RUNTIME_APK_PACKAGES` and `RUNTIME_PIP_PACKAGES` environment variables. This is useful for adding dependencies needed by specific plugins or custom workflows without rebuilding the image.

**⚠️ Note:** Runtime package installation happens at **every container start**, adding several seconds or more to startup time and requiring network access. For packages you always need, consider creating a custom image using the build-time `APK_RUNTIME_EXTRAS` and `PIP_EXTRAS` build arguments instead.

```bash
# Install some additional packages before starting
$ docker run -d --name beets \
  -e RUNTIME_APK_PACKAGES="curl" \
  -e RUNTIME_PIP_PACKAGES="beets-alternatives" \
  -p 8337:8337 \
  -v "$(pwd)/config:/config" \
  -v "$(pwd)/library:/library" \
  ghcr.io/treyturner/beets:v2.5.1
```


### Database trouble?

You can add `sqlite` to the container to debug or resolve problems with the beets database.

```bash
# If container isn't running...
docker run -it --rm -w /config -e RUNTIME_APK_PACKAGES="sqlite" ghcr.io/treyturner/beets:v2.5.1 sqlite3 library.db

# With container running...
docker exec -it -w /config beets bash -c 'apk add --no-cache sqlite && sqlite3 library.db'

```

## Configuration

Beets is extremely configurable; you'll want to read the [usage](https://beets.readthedocs.io/en/stable/reference/cli.html) and [configuration](https://beets.readthedocs.io/en/stable/reference/config.html) docs on how to create a `config.yaml` to put in `/config` and run the CLI to manage your library.

Make sure to set the `directory` setting in your config (e.g. `/library`) to match whatever mount you provide.

## Building Locally

```bash
docker build \
  --build-arg BEETS_REF=master \
  -t treyturner/beets:local-dev \
  .
```

Supported build args:

- `BEETS_REF`: The git ref of [`beetbox/beets`](https://github.com/beetbox/beets) to build (tag, branch, or SHA)
- `APK_BUILD_DEPS`, `APK_RUNTIME_EXTRAS`: space-separated Alpine packages.
- `PIP_EXTRAS` - space-separated Python packages (wheels) to bundle alongside beets.

## Contributing

I made this because I needed it. Questions, issue reports, and PRs are welcome and appreciated, or feel free to fork and make it more your own.

## License

Licensed via [The Unlicense](LICENSE).
