FROM nginx:latest

COPY index.html /usr/share/nginx/html/index.html
ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD ["nginx", "-g", "daemon off;"]