import json, boto3, os

client = boto3.client('dynamodb')

def lambda_handler(event, context):
    print(f"The user input is: {event}")   
    user_input_date = event['parameters'][0]['value']

    response = client.get_item(
        TableName=os.environ.get('TABLE_NAME'),
        Key={
            'date': {'S': user_input_date}
        }
    )

    room_inventory_data = response['Item']
    print(room_inventory_data)

    # format the response appropriate to the agent
    agent = event['agent']
    action_group = event['actionGroup']
    api_path = event['apiPath']

    get_parameters = event.get('parameters', [])

    response_body = {
     'application/json': {
        'body': json.dumps(room_inventory_data)
     }   
    }

    print(f"The response to the agent is {response_body}")

     action_response = {
        'actionGroup': event['actionGroup'],
        'apiPath': event['apiPath'],
        'httpMethod': event['httpMethod'],
        'httpStatusCode': 200,
        'responseBody': response_body
    }
    
    session_attributes = event['sessionAttributes']
    prompt_session_attributes = event['promptSessionAttributes']
    
    api_response = {
        'messageVersion': '1.0', 
        'response': action_response,
        'sessionAttributes': session_attributes,
        'promptSessionAttributes': prompt_session_attributes
    }
        
    return api_response
    print(f"The final response is {api_response}")
    