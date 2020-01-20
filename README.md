# kratos-gid-tester
GiD Tester project for Kratos Problemtype

## Run local
- Install nodejs
- `npm install`
- `npm start`

## Run docker
- In Windows (uses linux containers):
    - `./scripts/dockerON.bat`
- In Linux
    - `docker build -t kratos-tester .`
    - `docker run --name kratos-tester kratos-tester`
    