FROM python:3.11-slim
WORKDIR /app
RUN pip install rq-dashboard
COPY start.sh ./start.sh
RUN chmod +x ./start.sh
CMD ["/app/start.sh"]
