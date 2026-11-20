# Skills

[Back to README](../README.md)

The server can serve [Agent Skills](https://agentskills.io) alongside its tools, through the MCP
Skills extension (SEP-2640, `io.modelcontextprotocol/skills`). A skill is a directory with a
`SKILL.md` and the files it refers to. A client that supports the extension lists the skills with
`skills/list` and reads their files as `skill://<name>/...` resources. Ship a skill with the tools it
explains, so every client connected to the server gets both.

```ruby
Administrate::MCP.configure do |c|
  c.skill_paths = [Rails.root.join('config/mcp_skills')]
end
```

Each path holds skill directories, not a skill itself:

```
config/mcp_skills/
├── create-record/
│   ├── SKILL.md
│   └── references/
│       └── orders.md
└── review-record/
    └── SKILL.md
```

The directory name must equal the `name` of the frontmatter. The skills are read on the first
request that serves them, and their files are checked against that read on every request: restart
the application after changing them. Without `skill_paths` the server does not declare the
extension.

## Showing a skill to some admins only

`skill_visible` decides, for each request, which skills the server serves. A skill it rejects is
neither listed nor readable. It receives the skill and the server context, which holds `:admin` and
`:scopes`:

```ruby
c.skill_visible = lambda do |skill, server_context|
  skill.name != 'create-record' || server_context[:scopes].map(&:to_s).include?('write')
end
```

Hiding a skill only hides its instructions: the tools it uses still run their own scope and role
checks.
