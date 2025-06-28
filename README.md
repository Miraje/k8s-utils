# Utilitarian script for Kubernetes

A lightweight Bash utility to **list** or **compare** container images (including versions) across Kubernetes namespaces, with optional HTML report generation.

## 🗂️ Sections

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Usage](#usage)

   - [List mode](#1-list-mode)
   - [Compare mode](#2-compare-mode)

4. [Contributing](#contributing)

## 📦 Requirements

- `kubectl`
- `jq`
- Bash (with `set -euo pipefail` support)

## 🚀 Installation

1. Clone or download the repo:

   ```bash
   git clone <your-repo-url>
   cd <your-repo>
   ```

2. Make the script executable:

   ```bash
   chmod +x k8s-utils.sh
   ```

## 🧭 Usage

### 1. List mode

**Syntax:**

```bash
./k8s-utils.sh list [-c CONTEXT] -n NAMESPACE [--html FILE]
```

- `-c CONTEXT`: Specify kubeconfig context (optional - defaults to current context).
- `-n NAMESPACE`: Namespace to inspect.
- `--html FILE`: Generate HTML report to specified file (optional).

**Terminal output example:**

```console
$ ./k8s-utils.sh list -n sts-portal-dev --html sts-portal-dev-resources.html

+------------+------------+----------------+----------+
| TYPE       | NAME       | IMAGES         | VERSIONS |
+------------+------------+----------------+----------+
| Deployment | api-server | api-server     | v1.2.3   |
| Service    | frontend   |                |          |
+------------+------------+----------------+----------+

HTML file generated: sts-portal-dev-resources.html
```

### 2. Compare mode

**Syntax:**

```bash
./k8s-utils.sh compare [-c1 CTX1] -n1 NS1 [-c2 CTX2] -n2 NS2 [--html FILE]
```

- `-c1 CTX1` / `-c2 CTX2`: Specify kubeconfig context (optional - defaults to current context).
- `-n1 NS1` / `-n2 NS2`: Namespace(s) to inspect.
- `--html FILE`: Generate HTML report to specified file (optional).

**Terminal output example:**

```console
$  ./k8s-utils.sh compare -c1 dweustpaksblue -n1 sts-portal-dev -c2 iweustpaksblue -n2 sts-portal-int --html test.html

🔍 Differences
+------------+-------------+----------+----------+-----------+
| TYPE       | NAME        | IMAGES   | staging  | production |
+------------+-------------+----------+----------+-----------+
| Deployment | api-server  | api-srv  | v1.2.3   | v1.3.0    |
+------------+-------------+----------+----------+-----------+

✅ Matches
+--------+----------+----------+----------+-----------+
| TYPE   | NAME     | IMAGES   | staging  | production |
+--------+----------+----------+----------+-----------+
| Service| frontend | frontend | present  | present   |
+--------+----------+----------+----------+-----------+

HTML file generated: sts-portal-dev-resources.html
```

## 🤝 Contributing

Contributions are welcome!
