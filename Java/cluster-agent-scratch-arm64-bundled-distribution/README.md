# Scratch-based AppDynamics Cluster Agent Docker Image

This directory contains the implementation for a minimal, scratch-based Docker image for the AppDynamics Cluster Agent. This approach significantly reduces the image size and eliminates security vulnerabilities by removing all unnecessary components from the final image.

## Benefits

### Security
- **Zero OS vulnerabilities**: Scratch base has no OS packages that can contain vulnerabilities
- **Minimal attack surface**: Only contains the necessary binaries and files
- **No package manager**: Eliminates risks from package managers like apt/apk
- **No shell**: Removes shell-based attack vectors

### Size
- **Minimal size**: Only contains the cluster agent binary, CA certificates, and required files
- **Faster pulls**: Reduced image size means faster container startup
- **Lower storage costs**: Especially important in large-scale deployments

### Performance
- **Faster startup**: Less filesystem overhead
- **Lower memory footprint**: No unnecessary OS processes or files in memory
- **Clean runtime environment**: No background OS services

## Architecture

### Multi-stage Build
The Dockerfile uses a two-stage build process:

1. **Builder stage**: Uses Alpine Linux to set up the directory structure, extract binaries, and build the entrypoint wrapper
2. **Runtime stage**: Uses scratch base and copies only the necessary files from the builder stage

### Components

#### Files in Final Image
- `/opt/appdynamics/cluster-agent/cluster-agent` - Main cluster agent binary (statically linked)
- `/opt/appdynamics/cluster-agent/target-allocator` - Target allocator binary (statically linked)
- `/opt/appdynamics/cluster-agent/config/` - Configuration directory structure
- `/etc/ssl/certs/ca-certificates.crt` - CA certificates for HTTPS
- `/etc/passwd`, `/etc/group` - User information for non-root user
- `/licenses/` - License file

#### User Security
- Runs as user ID 9001 (non-root)
- No shell access (scratch base doesn't include shell)

## Usage

### Running the Container
The scratch-based image uses the same environment variables as the original Alpine-based image:

### Kubernetes Deployment
Update your Helm values or Kubernetes manifests to use the scratch-based image:

```yaml
image:
  repository: appdynamics/cluster-agent
  tag: scratch-latest
  pullPolicy: Always
```

## Implementation Details

### Static Linking
Both the cluster agent binaries are built with:
- `CGO_ENABLED=0` - Disables CGO for static linking
- `-a -ldflags '-extldflags "-static"'` - Forces static linking

### Directory Structure
The image maintains the expected directory structure:
```
/opt/appdynamics/cluster-agent/
├── cluster-agent (binary)
├── target-allocator (binary)
├── config/
│   ├── agent-monitoring/
│   │   └── agent-monitoring.yml
│   ├── instrumentation/
│   │   └── instrumentation.yml
│   ├── target-allocator/
│   │   └── config.yml
│   ├── agent-monitoring.yml (symlink)
│   ├── instrumentation.yml (symlink)
│   └── target-allocator.yml (symlink)
└── logs/
```

## Troubleshooting

### Debugging
Since there's no shell in the scratch image, debugging requires different approaches:

1. **Use docker exec with another image**:
   ```bash
   # Run a debug container with access to the same volumes
   kubectl run debug --image=alpine --rm -it -- sh
   ```

2. **Check logs**:
   ```bash
   kubectl logs <pod-name>
   ```

3. **Use init containers** for setup/debugging:
   ```yaml
   initContainers:
   - name: debug-init
     image: alpine
     command: ['sh', '-c', 'ls -la /opt/appdynamics/cluster-agent/']
   ```

### Common Issues

1. **Binary compatibility**: Ensure binaries are built for the correct architecture (amd64/arm64)
2. **File permissions**: The builder stage sets proper permissions for user 9001
3. **CA certificates**: HTTPS connections require the ca-certificates.crt file

## Security Considerations

### What's Removed
- Operating system packages (no vulnerabilities to patch)
- Package managers (apt, apk, yum)
- Shell interpreters (/bin/sh, /bin/bash)
- System utilities (grep, sed, awk, etc.)
- Unnecessary libraries

### What's Kept
- Only the essential binaries
- CA certificates for secure communications
- Minimal user information for non-root execution

This approach follows security best practices for containerized applications by minimizing the attack surface while maintaining full functionality.
