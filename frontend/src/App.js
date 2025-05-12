import React, { useState, useEffect } from "react";

function App() {
  const [name, setName] = useState("");
  const [data, setData] = useState([]);

  const handleSubmit = async () => {
    await fetch("http://<BACKEND_ALB_DNS>/api/user", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name })
    });
    setName("");
    fetchData();
  };

  const fetchData = async () => {
    const res = await fetch("http://<BACKEND_ALB_DNS>/api/users");
    const json = await res.json();
    setData(json);
  };

  useEffect(() => {
    fetchData();
  }, []);

  return (
    <div>
      <h1>User Form</h1>
      <input value={name} onChange={e => setName(e.target.value)} />
      <button onClick={handleSubmit}>Submit</button>
      <ul>
        {data.map((item, i) => (
          <li key={i}>{item.name}</li>
        ))}
      </ul>
    </div>
  );
}

export default App;
