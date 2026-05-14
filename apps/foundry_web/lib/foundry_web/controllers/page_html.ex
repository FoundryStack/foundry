defmodule FoundryWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use FoundryWeb, :html

  attr :root_id, :string, default: nil
  attr :canvas_id, :string, default: nil
  attr :panel_id, :string, default: nil
  attr :kicker, :string, required: true
  attr :state, :string, default: nil
  attr :title, :string, required: true
  attr :message, :string, required: true
  slot :inner_block

  def project_shell(assigns) do
    ~H"""
    <style>
      :root {
        --launch-bg-dark: #050408;
        --launch-orange: #fd4f00;
        --launch-orange-soft: rgba(253, 79, 0, 0.74);
      }

      .project-shell-root {
        min-height: 100vh;
        background:
          radial-gradient(circle at top, rgba(253, 79, 0, 0.1), transparent 32%),
          var(--launch-bg-dark);
        overflow: hidden;
      }

      .project-shell-canvas {
        position: fixed;
        inset: 0;
        width: 100vw;
        height: 100vh;
        z-index: 1;
        pointer-events: none;
        opacity: 0;
        transition: opacity 0.5s ease-in;
        filter: saturate(190%) brightness(150%) contrast(108%);
      }

      .project-shell-stage {
        position: relative;
        z-index: 10;
        display: flex;
        min-height: 100vh;
        align-items: center;
        justify-content: center;
        padding: 2rem 1.5rem;
        transition: opacity 0.5s ease;
      }

      .project-shell-panel {
        width: 100%;
        max-width: 46rem;
        text-align: center;
      }

      .project-shell-logo {
        display: block;
        width: auto;
        height: clamp(5rem, 12vw, 8.5rem);
        margin: 0 auto;
      }

      .project-shell-kicker {
        margin-top: 1rem;
        color: rgba(255, 255, 255, 0.48);
        font-size: 0.72rem;
        font-weight: 600;
        letter-spacing: 0.38em;
        text-transform: uppercase;
      }

      .project-shell-state {
        margin-top: 0.85rem;
        color: white;
        font-size: clamp(0.92rem, 1.7vw, 1.05rem);
        font-weight: 600;
        letter-spacing: 0.08em;
        text-transform: uppercase;
      }

      .project-shell-title {
        margin-top: 1rem;
        color: white;
        font-size: clamp(2rem, 4vw, 2.85rem);
        font-weight: 600;
        line-height: 1.1;
      }

      .project-shell-message {
        margin: 1rem auto 0;
        max-width: 34rem;
        color: rgba(255, 255, 255, 0.72);
        font-size: 1rem;
        line-height: 1.8;
      }
    </style>

    <div id={@root_id} class="project-shell-root">
      <canvas :if={@canvas_id} id={@canvas_id} class="project-shell-canvas"></canvas>

      <main class="project-shell-stage">
        <section id={@panel_id} class="project-shell-panel">
          <img class="project-shell-logo" src={~p"/images/foundry-logo.png"} alt="Foundry Logo" />
          <p class="project-shell-kicker">{@kicker}</p>
          <p :if={@state} class="project-shell-state">{@state}</p>
          <h1 class="project-shell-title">{@title}</h1>
          <p class="project-shell-message">{@message}</p>
          {render_slot(@inner_block)}
        </section>
      </main>
    </div>
    """
  end

  embed_templates "page_html/*"
end
