FROM arangodb:3.1

ADD ./run.sh /app/

EXPOSE 8529

ENTRYPOINT ["/app/run.sh"]
