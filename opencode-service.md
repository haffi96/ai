the systemd service file in ~/code is symlinked to ~/.config/systemd/user

the service should start opencode server and web ui exposed on port 4096

tailscale will service the port so its available on the tailnet 

the service should start on boot


commands:

systemctl --user status opencode-web

sudo tailscale serve -bg 4096
