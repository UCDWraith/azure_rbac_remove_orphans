# Use the official latest PowerShell container image
FROM mcr.microsoft.com/powershell:latest

# Install Git (VS Code requires Git inside dev containers)
RUN apt-get update && \
    apt-get install -y git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy setup script
COPY setup.ps1 /tmp/setup.ps1

# Install PowerShell modules
RUN pwsh -NoLogo -NoProfile -File /tmp/setup.ps1

# Use PowerShell as entrypoint
ENTRYPOINT ["/usr/bin/env", "pwsh"]

# Keep the container alive so VS Code can attach
CMD ["-NoLogo", "-NoProfile", "-Command", "while ($true) { Start-Sleep -Seconds 3600 }"]