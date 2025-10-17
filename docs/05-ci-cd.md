# VIGO — CI/CD Reference (Node + ASP.NET Core)

Start here for first-time setup: docs/00-zero-to-live.md

Publishing strategy
- Build and push two tags per commit:
  - `:sha-<GIT_SHA_SHORT>` immutable (primary tag pinned in infra)
  - `:branch-<branch>` mutable (optional for smoke testing)

Registry assumptions
- GitHub Container Registry (GHCR) examples use `ghcr.io/<org>/<name>`.
- Replace with your own registry (see also `docs/registry.md`).

GitHub Actions — Node (to GHCR)
File to copy into your app repo: `.github/workflows/build.yml`
```yaml
name: build
on:
  push:
    branches: [ main ]

jobs:
  docker:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata (tags)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository_owner }}/sampleapp
          tags: |
            type=raw,value=sha-${{ github.sha }}
            type=raw,value=branch-${{ github.ref_name }}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

GitHub Actions — ASP.NET Core (to GHCR)
```yaml
name: build
on:
  push:
    branches: [ main ]

jobs:
  docker:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata (tags)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository_owner }}/dotnetapp
          tags: |
            type=raw,value=sha-${{ github.sha }}
            type=raw,value=branch-${{ github.ref_name }}

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: .
          file: ./Dockerfile
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

GitLab CI — Node (to GitLab Registry)
`image: docker:24.0.5`
```yaml
stages: [ build ]

variables:
  IMAGE_NAME: $CI_REGISTRY_IMAGE
  SHA_TAG: sha-${CI_COMMIT_SHORT_SHA}
  BRANCH_TAG: branch-${CI_COMMIT_REF_SLUG}

build:
  stage: build
  services:
    - docker:24.0.5-dind
  script:
    - echo $CI_REGISTRY_PASSWORD | docker login -u $CI_REGISTRY_USER --password-stdin $CI_REGISTRY
    - docker build -t $IMAGE_NAME:$SHA_TAG -t $IMAGE_NAME:$BRANCH_TAG .
    - docker push $IMAGE_NAME:$SHA_TAG
    - docker push $IMAGE_NAME:$BRANCH_TAG
```

GitLab CI — ASP.NET Core (to GitLab Registry)
```yaml
stages: [ build ]

variables:
  IMAGE_NAME: $CI_REGISTRY_IMAGE
  SHA_TAG: sha-${CI_COMMIT_SHORT_SHA}
  BRANCH_TAG: branch-${CI_COMMIT_REF_SLUG}

build:
  stage: build
  image: docker:24.0.5
  services:
    - docker:24.0.5-dind
  script:
    - echo $CI_REGISTRY_PASSWORD | docker login -u $CI_REGISTRY_USER --password-stdin $CI_REGISTRY
    - docker build -t $IMAGE_NAME:$SHA_TAG -t $IMAGE_NAME:$BRANCH_TAG -f Dockerfile .
    - docker push $IMAGE_NAME:$SHA_TAG
    - docker push $IMAGE_NAME:$BRANCH_TAG
```

After publish
- Update `stacks/<app>/docker-compose.yml` to pin `image: ...:sha-<short>`.
- Commit and push to infra repo; VPS reconciles automatically.
