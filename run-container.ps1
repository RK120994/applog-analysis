docker build -t applog-web .
docker run -d -p 8080:80 --name applog-site applog-web
Write-Host "Site running: http://localhost:8080"