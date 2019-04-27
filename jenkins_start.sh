docker run -d \
  --name jenkins \
  --restart="always" \
  -p 8080:8080 \
  -p 50000:50000 \
  -v /var/run/docker.sock:/tmp/docker.sock \
  -v /srv/jenkins_home:/var/jenkins_home \
jenkins/jenkins:latest
