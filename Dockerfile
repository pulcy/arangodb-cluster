FROM arangodb/arangodb:3.0.1

ADD ./run.sh /app/

EXPOSE 8529

ENTRYPOINT ["/app/run.sh"]
