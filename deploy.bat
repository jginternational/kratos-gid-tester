

setlocal EnableDelayedExpansion

rem do not echo every command
@echo off

set version="Deploying kratos-tester:10.3.0"

echo %version%

git tag -f %version%
git push --tags --force
docker build -t kratos-tester:latest -t kratos-tester:%version% .

if %errorlevel% neq 0 (
    echo Error: Docker build failed.
    exit /b %errorlevel%
)

docker tag kratos-tester:%version% fjgarate/kratos-tester:%version%
docker push fjgarate/kratos-tester:%version%
docker tag kratos-tester:latest fjgarate/kratos-tester:latest
docker push fjgarate/kratos-tester:latest
