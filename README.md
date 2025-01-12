# action.publish-swarm-stack

Generates version locked docker-compose YAML files from a list of swarm stack templates. Can be used in a GitOps workflow to ensure you are running a particular version of a docker image rather than just "latest".

Use this action to schedule updates for your Portainer or Coolify deployments.

# Usage

<!-- start usage -->
```yaml
- uses: Josh5/action.publish-swarm-stack@master
  with:
    branch_name: release/latest
    # Branch name to which the Docker Swarm templates will be published.
    # Default: release/latest
    branch_name: ''

    # The directory in your git repository that contains the Docker Swarm templates.
    # Default: docker-swarm-templates
    templates_path: ''

    # Personal access token (PAT) used to push the repository.
    #
    # [Learn more about creating and using encrypted secrets](https://help.github.com/en/actions/automating-your-workflow-with-github-actions/creating-and-using-encrypted-secrets)
    #
    # Default: ${{ github.token }}
    github_token: ''
```
<!-- end usage -->

# Custom documentation

This action will generate a `README.md` and a `/docs` path. If your project's `templates_path` directory contains your own custom `README.md` and `/docs` directory, then they will be used instead.

The README.md will be customised. Add placeholders listed below to have the replaced by this action.

| Variable      | Replaced by String                            |
| ------------- | --------------------------------------------- |
| `<url>`       | `${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}`   |
| `<branch>`    | `${BRANCH_NAME:?}`                            |


# Example

Generate the a release branch `release/latest` with the latest docker-compose YAML templates that are in the /docker-swarm-templates directory of your repo:
```yaml
  build-swarm-stack-templates:
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/master'
    permissions:
      contents: write
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Publish Swarm Template
        uses: Josh5/action.publish-swarm-stack@master
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          templates_path: docker-swarm-templates
          branch_name: release/latest
```
