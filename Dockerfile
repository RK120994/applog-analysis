FROM nginx:alpine

# Copy static report assets
COPY report /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
