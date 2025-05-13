const express = require("express");
const AWS = require("aws-sdk");
const cors = require("cors");
const bodyParser = require("body-parser");

const app = express();
app.use(cors());
app.use(bodyParser.json());

AWS.config.update({ region: "us-east-1" });
const ddb = new AWS.DynamoDB.DocumentClient();
const TABLE_NAME = "Users";

app.post("/api/user", async (req, res) => {
  const { name } = req.body;
  await ddb.put({
    TableName: TABLE_NAME,
    Item: { id: Date.now().toString(), name }
  }).promise();
  res.send({ status: "OK" });
});

app.get("/api/users", async (_, res) => {
  const data = await ddb.scan({ TableName: TABLE_NAME }).promise();
  res.send(data.Items);
});

app.listen(3000, () => console.log("Server running on port 3000"));

