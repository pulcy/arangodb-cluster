FROM arangodb:3.0

ADD ./run.sh /app/

EXPOSE 5007
EXPOSE 8259

ENTRYPOINT ["/app/run.sh"]
