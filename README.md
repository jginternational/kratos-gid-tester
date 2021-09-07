# kratos-gid-tester
GiD Tester project for Kratos Problemtype

## Option A: Run local
- Check GiD & tester location
- Install nodejs
- `npm install`
- `npm start`

## Option B: Run docker
- In Windows (uses linux containers):
    - `./scripts/dockerON.bat`
- In Linux
    - `docker build -t kratos-tester .`
    - `docker run --name kratos-tester kratos-tester`
    
