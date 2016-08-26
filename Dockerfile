FROM arangodb/arangodb:3.0.5

ADD ./run.sh /app/

EXPOSE 8529

ENTRYPOINT ["/app/run.sh"]
