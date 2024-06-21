import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots

# Load your data
fishing_data = pd.read_excel('fishing-trip.xlsx')

fishing_data['depth'] = (fishing_data['depth'] * -1)

print(fishing_data.head())

# Extract hour for time analysis
fishing_data['hour'] = fishing_data['datetime'].dt.hour

time_group = fishing_data.groupby('hour').agg(
    number_of_fish=('length', 'count'),
    average_size=('length', 'mean')
).reset_index()

# Create subplots
fig = make_subplots(rows=2, cols=1, subplot_titles=("Depth Analysis with Violin Plot", "Time of Day vs Number and Size of Fish"))

# Plot for depth analysis with violin plot
fig.add_trace(
    go.Violin(y=fishing_data['depth'], x=fishing_data['length'], name='Fish by Depth', 
              points='all', box_visible=True, meanline_visible=True, pointpos=0, orientation='h', scalemode='count'),
    row=1, col=1
)

# Add marker size based on fish length to the violin plot
# This is not natively supported in Plotly's violin plots, but you can overlay a scatter plot for a similar effect:
fig.add_trace(
    go.Scatter(x=fishing_data['length'], y=fishing_data['depth'], mode='markers', 
               marker=dict(size=fishing_data['length'], sizemode='diameter', sizeref=0.5), 
               name='Fish Sizes'),
    row=1, col=1
)

# Plot for time analysis
fig.add_trace(
    go.Bar(x=time_group['hour'], y=time_group['number_of_fish'], name='Number of Fish'),
    row=2, col=1
)
fig.add_trace(
    go.Scatter(x=time_group['hour'], y=time_group['average_size'], name='Average Size', mode='lines+markers'),
    row=2, col=1
)

# Update layout for clarity
fig.update_layout(height=800, showlegend=True, title_text="Fishing Trip Analysis Dashboard")
fig.show()
