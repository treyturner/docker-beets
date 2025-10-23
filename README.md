# docker-beets

Packages the upstream [`beetbox/beets`](https://github.com/beetbox/beets)
music manager on a Alpine base, optional build extras, and an entrypoint that
handles UID/GID mapping at runtime. Images published to Docker Hub and GHCR.

## Available Images

- [GHCR](https://github.com/treyturner/docker-beets/pkgs/container/beets): `ghcr.io/treyturner/beets`
- [Docker Hub](https://hub.docker.com/r/treyturner/beets): `docker.io/treyturner/beets`

### Tag Strategy

- `${BEETS_REF}-dev` – latest dev image produced from merges to this repo’s `main` branch.
- `${BEETS_REF}-dev<run_id>.<attempt_id>` – build-specific dev image for traceability
  (e.g. `v2.5.1-dev123456789.1`).
- `vX.Y.Z` – manual builds that pin the upstream beets release tag (e.g. `v2.5.1`).
- `latest`, `stable` – assignable aliases via the promotion workflow.

## Bundled Packages

### Beets + plugins:

- `beets[discogs,beatport]`
- `beets-beatport4`
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

|  Variable  |                 Description                  |  Default  |
| :--------: | :------------------------------------------: | :-------: |
|   `PUID`   | Numeric user ID that the entrypoint creates  |   `99`    |
|   `PGID`   | Numeric group ID that the entrypoint creates |   `100`   |
|  `UMASK`   |      Mask applied before spawning beets      |  `0022`   |
| `BEETSDIR` |           Path to the beets config           | `/config` |

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

The default command launches the [`web` plugin](https://beets.readthedocs.io/en/stable/plugins/web.html)'s HTTP server. If `$BEETSDIR/config.yaml` doesn't exist, the container loads with `beet -p web web`, but invoking in this fashion overrides any plugins listed in the config.

If no config exists the entrypoint creates one with `web.host: 0.0.0.0`; otherwise it merges in the `web` plugin and ensures the host binding is present before starting the server.

```bash
$ docker run -d --rm --name beets \
  -p 8337:8337 \
  -v "$(pwd)/config:/config" \
  -v "$(pwd)/library:/library" \
  treyturner/beets:v2.5.1

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

### Database trouble?

You can add `sqlite` to the container to debug or resolve problems with the beets database.

```bash
# With container running...
docker exec -it --rm beets bash -c 'apk add --no-cache sqlite && bash'

```

## Configuration

Beets is extremely configurable; you'll want to read the [usage](https://beets.readthedocs.io/en/stable/reference/cli.html) and [configuration](https://beets.readthedocs.io/en/stable/reference/config.html) docs on how to create a `config.yaml` to put in `/config` and run the CLI to manage your library.

Make sure to set the `directory` setting in your config (e.g. `/music`) to match whatever mount you provide.

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

## License

Apache 2.0. See `LICENSE` for details.
