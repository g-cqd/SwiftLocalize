# CI/CD Integration Guide

This guide covers integrating SwiftLocalize into your continuous integration and continuous deployment pipelines.

## Exit Codes

SwiftLocalize uses specific exit codes for CI/CD integration:

| Code | Meaning |
|------|---------|
| 0 | Success - all operations completed |
| 1 | Translation/validation errors occurred |
| 2 | Configuration errors |

## CI Mode

Use the `--ci` flag to enable CI-optimized behavior:

```bash
swiftlocalize translate --ci
swiftlocalize validate --ci
```

CI mode enables:
- JSON output for machine parsing
- Strict validation (fails on warnings)
- Minimal console output
- Non-interactive operation

## GitHub Actions

### Basic Translation Workflow

```yaml
name: Translate Strings

on:
  push:
    branches: [main]
    paths:
      - '**/*.xcstrings'
  workflow_dispatch:

jobs:
  translate:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Swift
        uses: swift-actions/setup-swift@v2
        with:
          swift-version: '6.0'

      - name: Build SwiftLocalize
        run: swift build -c release

      - name: Translate Strings
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
        run: |
          swift run -c release swiftlocalize translate --ci

      - name: Commit Changes
        run: |
          git config --local user.email "action@github.com"
          git config --local user.name "GitHub Action"
          git add *.xcstrings
          git diff --staged --quiet || git commit -m "chore: Update translations [skip ci]"
          git push
```

### Validation Only

```yaml
name: Validate Translations

on:
  pull_request:
    paths:
      - '**/*.xcstrings'

jobs:
  validate:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build SwiftLocalize
        run: swift build -c release

      - name: Validate Translations
        run: swift run -c release swiftlocalize validate --ci

      - name: Check Translation Status
        run: swift run -c release swiftlocalize status --json
```

### Scheduled Translation Updates

```yaml
name: Weekly Translation Update

on:
  schedule:
    - cron: '0 0 * * 0'  # Every Sunday at midnight
  workflow_dispatch:

jobs:
  update-translations:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4

      - name: Translate with Backup
        env:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
        run: |
          swift run swiftlocalize translate --backup --ci

      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v5
        with:
          title: 'chore: Weekly translation update'
          body: 'Automated translation update from SwiftLocalize'
          branch: translations/weekly-update
```

## GitLab CI

### .gitlab-ci.yml

```yaml
stages:
  - validate
  - translate

variables:
  SWIFT_VERSION: "6.0"

validate-translations:
  stage: validate
  image: swiftlang/swift:nightly-6.0-jammy
  script:
    - swift build -c release
    - swift run -c release swiftlocalize validate --ci
  only:
    changes:
      - "**/*.xcstrings"

translate-strings:
  stage: translate
  image: swiftlang/swift:nightly-6.0-jammy
  script:
    - swift build -c release
    - swift run -c release swiftlocalize translate --ci
    - git add *.xcstrings
    - git commit -m "Update translations" || true
    - git push origin HEAD:$CI_COMMIT_REF_NAME
  only:
    - main
  when: manual
```

## Azure DevOps

### azure-pipelines.yml

```yaml
trigger:
  paths:
    include:
      - '**/*.xcstrings'

pool:
  vmImage: 'macOS-latest'

steps:
  - task: UseSwiftVersion@1
    inputs:
      version: '6.0'

  - script: swift build -c release
    displayName: 'Build SwiftLocalize'

  - script: swift run -c release swiftlocalize validate --ci
    displayName: 'Validate Translations'

  - script: |
      swift run -c release swiftlocalize translate --ci
      git add *.xcstrings
      git commit -m "Update translations" || exit 0
      git push
    displayName: 'Translate and Commit'
    env:
      OPENAI_API_KEY: $(OPENAI_API_KEY)
```

## Bitrise

### bitrise.yml

```yaml
workflows:
  translate:
    steps:
      - git-clone: {}

      - script:
          title: Install Swift
          inputs:
            - content: |
                swift --version

      - script:
          title: Build SwiftLocalize
          inputs:
            - content: swift build -c release

      - script:
          title: Translate Strings
          inputs:
            - content: |
                swift run -c release swiftlocalize translate --ci
          envs:
            - OPENAI_API_KEY: $OPENAI_API_KEY

      - script:
          title: Commit Changes
          inputs:
            - content: |
                git add *.xcstrings
                git commit -m "Update translations" || exit 0
                git push
```

## CircleCI

### .circleci/config.yml

```yaml
version: 2.1

jobs:
  translate:
    macos:
      xcode: "16.0.0"
    steps:
      - checkout
      - run:
          name: Build SwiftLocalize
          command: swift build -c release
      - run:
          name: Translate Strings
          command: swift run -c release swiftlocalize translate --ci
          environment:
            OPENAI_API_KEY: ${OPENAI_API_KEY}
      - run:
          name: Commit Changes
          command: |
            git add *.xcstrings
            git commit -m "Update translations" || true
            git push

workflows:
  weekly-translation:
    triggers:
      - schedule:
          cron: "0 0 * * 0"
          filters:
            branches:
              only: main
    jobs:
      - translate
```

## Parsing JSON Output

When using `--ci` or `--json` flags, SwiftLocalize outputs machine-readable JSON:

### Translation Result

```json
{
  "totalStrings": 42,
  "translatedCount": 38,
  "failedCount": 0,
  "skippedCount": 4,
  "durationSeconds": 12.5,
  "byLanguage": {
    "fr": {
      "translatedCount": 38,
      "failedCount": 0,
      "provider": "openai"
    }
  },
  "errors": []
}
```

### Status Output

```json
{
  "files": [
    {
      "file": "Localizable.xcstrings",
      "totalStrings": 42,
      "languages": {
        "fr": {
          "translated": 42,
          "missing": 0,
          "percentage": 100.0
        },
        "de": {
          "translated": 38,
          "missing": 4,
          "percentage": 90.5
        }
      }
    }
  ]
}
```

### Parsing in Scripts

```bash
# Get translation count
swift run swiftlocalize translate --ci | jq '.translatedCount'

# Check for failures
FAILED=$(swift run swiftlocalize translate --ci | jq '.failedCount')
if [ "$FAILED" -gt 0 ]; then
  echo "Translation failures detected!"
  exit 1
fi

# Get completion percentage for a language
swift run swiftlocalize status --json | jq '.files[0].languages.fr.percentage'
```

## Best Practices

### 1. Use Secrets for API Keys

Never commit API keys to your repository. Use your CI/CD platform's secrets management:

- GitHub: Repository or Organization secrets
- GitLab: CI/CD Variables
- Azure DevOps: Pipeline Variables
- Bitrise: Secrets

### 2. Skip CI for Translation Commits

Add `[skip ci]` to commit messages to prevent infinite loops:

```bash
git commit -m "chore: Update translations [skip ci]"
```

### 3. Run Validation on PRs

Always validate translations in pull request checks:

```yaml
on:
  pull_request:
    paths:
      - '**/*.xcstrings'
```

### 4. Use Caching

Cache the SwiftLocalize build to speed up CI:

```yaml
- uses: actions/cache@v3
  with:
    path: .build
    key: ${{ runner.os }}-spm-${{ hashFiles('Package.resolved') }}
```

### 5. Backup Before Production Runs

Use `--backup` flag for production translation runs:

```bash
swiftlocalize translate --backup --ci
```

### 6. Monitor Translation Costs

Track API usage by parsing JSON output and sending metrics to your monitoring system.

## Troubleshooting

### Common Issues

**Build failures on Linux:**
SwiftLocalize requires macOS for Apple Translation framework support. Use `macos-latest` runners.

**API rate limits:**
Reduce batch size in configuration or add delays between runs.

**Git push failures:**
Ensure your CI token has push permissions to the repository.

**Missing translations:**
Check that target languages are configured in `.swiftlocalize.json`.
